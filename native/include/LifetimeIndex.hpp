#pragma once
#include <cstdint>
#include <deque>
#include <limits>
#include <mutex>
#include <unordered_map>

namespace MCT
{
// Non-owning identities. Only observed objects are retained, never Unreal references.
// Listener callbacks invalidate immediately; Lua consumes loss IDs at lifecycle events.
class LifetimeIndex
{
public:
    using Address = std::uintptr_t;
    using Token = std::uint64_t;
private:
    struct Entry { std::int32_t index; Token token; };
    mutable std::mutex mutex_;
    std::unordered_map<Address, Entry> live_;
    std::deque<Token> lost_;
    Token next_ = 1;
    bool active_ = false;

    void invalidate(std::unordered_map<Address, Entry>::iterator found)
    {
        if (found == live_.end()) return;
        const auto token = found->second.token;
        live_.erase(found); // Invalidation must survive notification-allocation failure.
        try { lost_.push_back(token); }
        catch (...) { active_ = false; live_.clear(); lost_.clear(); }
    }
public:
    void start() { std::scoped_lock lock(mutex_); active_ = true; }

    // probe runs under the listener lock, and must validate the object-array slot.
    // The caller must supply a fresh live object on the game thread.
    template<class Probe> Token capture(Address address, Probe probe)
    {
        std::scoped_lock lock(mutex_);
        if (!active_ || !address) return 0;
        const auto index = probe(address);
        if (index < 0) return 0;
        const auto found = live_.find(address);
        if (found != live_.end())
        {
            if (found->second.index == index) return found->second.token;
            invalidate(found);
        }
        // Exhaustion fails closed instead of ever reusing an identity.
        if (!active_) return 0;
        if (next_ == std::numeric_limits<Token>::max()) return 0;
        const auto token = next_++;
        live_.emplace(address, Entry{index, token});
        return token;
    }
    bool valid(Address address, Token token) const
    {
        std::scoped_lock lock(mutex_);
        const auto found = live_.find(address);
        return active_ && token && found != live_.end() && found->second.token == token;
    }
    void created(Address address)
    {
        std::scoped_lock lock(mutex_);
        // Replacement is a new lifetime even if address AND array index are reused.
        invalidate(live_.find(address));
    }
    void deleted(Address address, std::int32_t index)
    {
        std::scoped_lock lock(mutex_);
        const auto found = live_.find(address);
        if (found != live_.end() && found->second.index == index) invalidate(found);
    }
    Token takeLost()
    {
        std::scoped_lock lock(mutex_);
        if (lost_.empty()) return 0;
        const auto token = lost_.front(); lost_.pop_front(); return token;
    }
    void reset()
    {
        std::scoped_lock lock(mutex_);
        live_.clear(); lost_.clear(); // Lua session stopped; never reset next_.
    }
    void shutdown()
    {
        std::scoped_lock lock(mutex_);
        active_ = false;
        try
        {
            for (const auto& [address, entry] : live_) { (void)address; lost_.push_back(entry.token); }
        }
        catch (...) { lost_.clear(); }
        live_.clear();
    }
};
}
