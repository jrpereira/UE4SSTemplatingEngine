#include "TemplateRegistry.hpp"
#include <iostream>
#include <stdexcept>
#include <thread>
static void check(bool condition) { if (!condition) throw std::runtime_error("template registry check failed"); }
int main()
{
    MCT::TemplateRegistry registry;
    using Added = MCT::TemplateRegistry::Added;
    check(registry.add("C:\\Mods\\Fangdango\\ModCore\\templates\\wheel.lua") == Added::yes);
    check(registry.add("c:/mods/fangdango/modcore/templates/WHEEL.LUA") == Added::duplicate);
    check(registry.add("C:/Mods/Fangdango/Scripts/not_a_template.lua") == Added::invalid);
    check(registry.add("C:/Mods/Fangdango/ModCore/templates/bad\nfile.lua") == Added::invalid);
    std::thread other([&] { check(registry.add("Other/ModCore/templates/bar.lua") == Added::yes); });
    other.join();
    auto paths = registry.closeAndTake();
    check(paths.size() == 2 && paths[0] == "C:/Mods/Fangdango/ModCore/templates/wheel.lua");
    check(!registry.isOpen() && registry.add("Other/ModCore/templates/late.lua") == Added::closed);
    check(registry.closeAndTake().empty());
    registry.reopen();
    check(registry.add("Other/ModCore/templates/late.lua") == Added::yes);
    check(registry.closeAndTake().size() == 1);
    std::cout << "PASS: cross-module template registration and Loop Start closure\n";
}
