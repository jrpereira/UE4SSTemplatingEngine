#include "UE4SSABI.hpp"
#include "LoopStartQueue.hpp"
#include "LoopStartLua.hpp"
#include "NativeLifetimes.hpp"
#include "TemplateRegistry.hpp"
#include <charconv>
#include <mutex>

#ifdef _WIN32
#ifndef MCT_LUA_MOD_NAME
#define MCT_LUA_MOD_NAME L"_ModCore_Templates"
#endif

namespace
{
using RC::LuaMadeSimple::Lua;
class ModCoreTemplates final : public RC::CppUserModBase
{
    MCT::LoopStartQueue pending_;
    MCT::NativeLifetimes lifetimes_;
    MCT::TemplateRegistry templates_;
    std::mutex sessionMutex_;
    std::int64_t session_ = 0, nextSession_ = 1;
    inline static ModCoreTemplates* instance_ = nullptr;
    static int registerTemplate(const Lua& lua)
    {
        const auto value = lua.get_string(1);
        const auto result = instance_->templates_.add(value);
        lua.set_bool(result == MCT::TemplateRegistry::Added::yes
            || result == MCT::TemplateRegistry::Added::duplicate);
        if (result == MCT::TemplateRegistry::Added::closed) lua.set_string("registration closed at Loop Start");
        else if (result == MCT::TemplateRegistry::Added::invalid) lua.set_string("expected a ModCore/templates/*.lua path");
        else lua.set_nil();
        return 2;
    }
    static int takeRegistered(const Lua& lua)
    {
        const auto session = lua.get_integer(1);
        std::scoped_lock lock(instance_->sessionMutex_);
        if (!session || session != instance_->session_)
        {
            lua.set_nil(); return 1;
        }
        auto paths = instance_->templates_.closeAndTake();
        std::string joined;
        for (const auto& path : paths) { joined += path; joined += '\n'; }
        lua.set_string(joined);
        return 1;
    }
    static int lifetimeSession(const Lua& lua)
    {
        std::scoped_lock lock(instance_->sessionMutex_);
        lua.set_integer(instance_->session_); return 1;
    }
    static int capture(const Lua& lua)
    {
        std::scoped_lock lock(instance_->sessionMutex_);
        const auto session = lua.get_integer(1);
        const auto address = static_cast<std::uintptr_t>(lua.get_integer(1));
        const auto token = session && session == instance_->session_ ? instance_->lifetimes_.capture(address) : 0;
        if (token) lua.set_string(std::to_string(token)); else lua.set_nil();
        return 1;
    }
    static int valid(const Lua& lua)
    {
        std::scoped_lock lock(instance_->sessionMutex_);
        const auto session = lua.get_integer(1);
        const auto address = static_cast<std::uintptr_t>(lua.get_integer(1));
        const auto value = lua.get_string(1);
        MCT::LifetimeIndex::Token token{};
        const auto parsed = std::from_chars(value.data(), value.data() + value.size(), token);
        lua.set_bool(session && session == instance_->session_ && parsed.ec == std::errc{}
            && parsed.ptr == value.data() + value.size() && instance_->lifetimes_.valid(address, token));
        return 1;
    }
    static int takeLost(const Lua& lua)
    {
        std::scoped_lock lock(instance_->sessionMutex_);
        const auto session = lua.get_integer(1);
        const auto token = session && session == instance_->session_ ? instance_->lifetimes_.takeLost() : 0;
        if (token) lua.set_string(std::to_string(token)); else lua.set_nil();
        return 1;
    }
public:
    ModCoreTemplates()
    {
        instance_ = this;
        ModName = L"ModCore Templates lifecycle";
        ModVersion = L"0.0.20";
        ModDescription = L"One-shot notification after all Lua modules have loaded";
        ModAuthors = L"ModCore";
    }
    ~ModCoreTemplates() override { lifetimes_.stop(); instance_ = nullptr; }
    void on_unreal_init() override { lifetimes_.start(); }
    void on_lua_start(RC::StringViewType name, Lua& lua, Lua&, Lua&, Lua*) override
    {
        lua.register_function("MCTRegisterTemplate", &registerTemplate);
        if (name != MCT_LUA_MOD_NAME) return;
        {
            std::scoped_lock lock(sessionMutex_);
            lifetimes_.reset(); session_ = nextSession_++;
        }
        lua.register_function("MCTNativeTakeRegisteredTemplates", &takeRegistered);
        lua.register_function("MCTNativeLifetimeSession", &lifetimeSession);
        lua.register_function("MCTNativeCapture", &capture);
        lua.register_function("MCTNativeValid", &valid);
        lua.register_function("MCTNativeTakeLost", &takeLost);
        lua.execute_string(MCT::loop_start_lua);
        const auto dispatch = lua.registry().make_ref();
        pending_.add(lua.get_lua_state(), [&lua, dispatch] {
            lua.registry().get_function_ref(dispatch);
            lua.call_function(0, 0);
        });
    }
    void on_lua_stop(RC::StringViewType name, Lua& lua, Lua&, Lua&, Lua*) override
    {
        if (name != MCT_LUA_MOD_NAME) return;
        pending_.cancel(lua.get_lua_state());
        std::scoped_lock lock(sessionMutex_);
        session_ = 0; lifetimes_.reset(); templates_.reopen();
    }
    void on_update() override
    {
        // UE4SS calls mod updates after start_lua_mods() returns for the whole batch.
        // Each MCT Lua session is notified once; later updates perform no discovery.
        pending_.firstUpdate([] {
            OutputDebugStringA("[MCT] Failed to deliver the one-shot Loop Start notification\n");
        });
    }
};
}
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new ModCoreTemplates(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
#endif
