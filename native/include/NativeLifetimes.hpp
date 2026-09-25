#pragma once
#include "UE4SSABI.hpp"
#include "LifetimeIndex.hpp"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

namespace MCT
{
class NativeLifetimes
{
    LifetimeIndex index_;
    struct Created final : RC::Unreal::FUObjectCreateListener
    {
        NativeLifetimes& owner;
        bool registered = false;
        explicit Created(NativeLifetimes& value) : owner(value) {}
        void NotifyUObjectCreated(const RC::Unreal::UObjectBase* object, std::int32_t) override
        { owner.index_.created(reinterpret_cast<std::uintptr_t>(object)); }
        void OnUObjectArrayShutdown() override { owner.index_.shutdown(); remove(); }
        void remove()
        {
            if (!registered) return;
            registered = false;
            RC::Unreal::FUObjectArray::RemoveUObjectCreateListener(this);
        }
    } created_{*this};
    struct Deleted final : RC::Unreal::FUObjectDeleteListener
    {
        NativeLifetimes& owner;
        bool registered = false;
        explicit Deleted(NativeLifetimes& value) : owner(value) {}
        void NotifyUObjectDeleted(const RC::Unreal::UObjectBase* object, std::int32_t index) override
        { owner.index_.deleted(reinterpret_cast<std::uintptr_t>(object), index); }
        void OnUObjectArrayShutdown() override { owner.index_.shutdown(); remove(); }
        void remove()
        {
            if (!registered) return;
            registered = false;
            RC::Unreal::FUObjectArray::RemoveUObjectDeleteListener(this);
        }
    } deleted_{*this};
    template<class T> static bool read(std::uintptr_t address, T& value)
    {
        SIZE_T copied{};
        return address && ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(address),
            &value, sizeof(value), &copied) && copied == sizeof(value);
    }
public:
    ~NativeLifetimes() { stop(); }
    void start()
    {
        if (created_.registered && deleted_.registered) return;
        try
        {
            RC::Unreal::FUObjectArray::AddUObjectCreateListener(&created_); created_.registered = true;
            RC::Unreal::FUObjectArray::AddUObjectDeleteListener(&deleted_); deleted_.registered = true;
            index_.start();
        }
        catch (...) { stop(); throw; }
    }
    void stop() { index_.shutdown(); created_.remove(); deleted_.remove(); }
    void reset() { index_.reset(); }
    LifetimeIndex::Token capture(std::uintptr_t address)
    {
        if (!RC::Unreal::IsInGameThread()) return 0;
        return index_.capture(address, [](std::uintptr_t pointer) -> std::int32_t {
            // Verified offsets for this Dawnwalker/UE5.5 target, not a general UE ABI.
            // Avoid UE4SS's problematic exported FWeakObjectPtr constructor.
            std::int32_t slot = -1;
            if (!read(pointer + 0x0C, slot) || slot < 0) return -1;
            const auto item = RC::Unreal::FUObjectArray::IndexToObject(slot);
            std::uintptr_t live{};
            if (!read(reinterpret_cast<std::uintptr_t>(item), live) || live != pointer) return -1;
            return slot;
        });
    }
    bool valid(std::uintptr_t address, LifetimeIndex::Token token) const
    { return RC::Unreal::IsInGameThread() && index_.valid(address, token); }
    LifetimeIndex::Token takeLost()
    { return RC::Unreal::IsInGameThread() ? index_.takeLost() : 0; }
};
}
#endif
