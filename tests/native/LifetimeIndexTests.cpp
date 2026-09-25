#include "LifetimeIndex.hpp"
#include <iostream>
#include <stdexcept>
#include <thread>
static void check(bool value) { if (!value) throw std::runtime_error("lifetime index check failed"); }
int main()
{
    MCT::LifetimeIndex index;
    const auto probe = [](auto) { return 7; };
    check(index.capture(100, probe) == 0);
    index.start();
    check(index.capture(0, probe) == 0);
    check(index.capture(100, [](auto) { return -1; }) == 0);
    const auto first = index.capture(100, probe);
    check(first && index.capture(100, probe) == first && index.valid(100, first));
    index.deleted(100, 8); check(index.valid(100, first)); // wrong slot cannot revoke
    std::thread deletion([&] { index.deleted(100, 7); }); deletion.join();
    check(!index.valid(100, first));
    const auto replacement = index.capture(100, probe);
    check(replacement != first && index.valid(100, replacement));
    check(index.takeLost() == first && index.takeLost() == 0);
    index.created(100); // independently guards reuse at creation
    check(!index.valid(100, replacement));
    const auto third = index.capture(100, probe);
    check(third != replacement && index.takeLost() == replacement);
    const auto fourth = index.capture(100, [](auto) { return 9; });
    check(fourth != third && index.takeLost() == third);
    check(!index.valid(101, fourth));
    index.reset(); check(!index.valid(100, fourth) && index.takeLost() == 0);
    const auto afterReload = index.capture(100, probe);
    check(afterReload > fourth);
    index.shutdown(); check(!index.valid(100, afterReload));
    check(index.takeLost() == afterReload && index.capture(100, probe) == 0);
    index.start(); check(index.capture(100, probe) > afterReload);
    // Concurrent native deletion never needs to enter Lua or dereference an object.
    for (int i = 0; i < 1000; ++i)
    {
        const auto token = index.capture(200, probe);
        std::thread worker([&] { index.deleted(200, 7); });
        (void)index.valid(200, token); worker.join();
        check(!index.valid(200, token) && index.takeLost() == token);
    }
    std::cout << "PASS: native lifetime reuse, reload, shutdown and concurrent deletion checks\n";
}
