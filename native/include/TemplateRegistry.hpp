#pragma once
#include <algorithm>
#include <cctype>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

namespace MCT
{
// Native registry is shared across isolated UE4SS Lua states. It closes exactly
// at MCT's one-shot all-modules Loop Start notification.
class TemplateRegistry
{
    mutable std::mutex mutex_;
    std::vector<std::string> paths_;
    std::unordered_set<std::string> keys_;
    bool open_ = true;
    static std::string canonical(std::string_view path)
    {
        std::string result(path);
        std::replace(result.begin(), result.end(), '\\', '/');
        return result;
    }
    static std::string fold(std::string path)
    {
        for (auto& c : path) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return path;
    }
public:
    enum class Added { yes, duplicate, closed, invalid };
    Added add(std::string_view path)
    {
        auto clean = canonical(path);
        if (clean.empty() || clean.size() > 4096 || clean.find_first_of("\r\n\0",0,2) != std::string::npos)
            return Added::invalid;
        auto key = fold(clean);
        if (key.size() < 4 || key.substr(key.size()-4) != ".lua"
            || key.find("/modcore/templates/") == std::string::npos) return Added::invalid;
        std::scoped_lock lock(mutex_);
        if (!open_) return Added::closed;
        if (!keys_.insert(key).second) return Added::duplicate;
        paths_.push_back(std::move(clean));
        return Added::yes;
    }
    std::vector<std::string> closeAndTake()
    {
        std::scoped_lock lock(mutex_);
        open_ = false;
        keys_.clear();
        auto result = std::move(paths_);
        paths_.clear();
        return result;
    }
    void reopen()
    {
        std::scoped_lock lock(mutex_);
        paths_.clear(); keys_.clear(); open_ = true;
    }
    bool isOpen() const { std::scoped_lock lock(mutex_); return open_; }
};
}
