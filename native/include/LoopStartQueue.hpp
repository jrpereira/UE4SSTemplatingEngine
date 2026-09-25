#pragma once
#include <functional>
#include <memory>
#include <unordered_map>
#include <utility>
#include <vector>

namespace MCT
{
// Called only by UE4SS's module-loading/event-loop thread. No timer or object scan.
class LoopStartQueue
{
    struct Session
    {
        bool active{true};
        std::function<void()> notify;
    };
    std::unordered_map<void*, std::shared_ptr<Session>> sessions_;
    std::vector<std::shared_ptr<Session>> pending_;

public:
    void add(void* key, std::function<void()> notify)
    {
        cancel(key);
        auto session = std::make_shared<Session>();
        session->notify = std::move(notify);
        sessions_.emplace(key, session);
        pending_.push_back(std::move(session));
    }
    void cancel(void* key)
    {
        const auto found = sessions_.find(key);
        if (found == sessions_.end()) return;
        found->second->active = false;
        found->second->notify = {};
        sessions_.erase(found);
    }
    template <typename OnError>
    void firstUpdate(OnError on_error)
    {
        auto pending = std::move(pending_);
        pending_.clear();
        for (auto& session : pending)
        {
            if (!session->active || !session->notify) continue;
            // Consume before invoking so an exception or reentrant update cannot repeat it.
            auto notify = std::move(session->notify);
            try { notify(); }
            catch (...) { on_error(); }
        }
    }
};
}
