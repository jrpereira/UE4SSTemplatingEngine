#include "LoopStartQueue.hpp"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
static void check(bool value) { if (!value) throw std::runtime_error("startup queue check failed"); }
int main()
{
    MCT::LoopStartQueue queue;
    int first{}, second{}, errors{}, key1{}, key2{};
    auto error = [&] { ++errors; };
    queue.add(&key1, [&] { ++first; });
    check(first == 0); // registration during module loading never fires synchronously
    queue.firstUpdate(error); queue.firstUpdate(error);
    check(first == 1);
    queue.add(&key1, [&] { ++first; }); queue.cancel(&key1);
    queue.firstUpdate(error); check(first == 1);
    queue.add(&key1, [&] { ++first; });
    queue.add(&key1, [&] { first += 10; }); // reused Lua state address, old session cancelled
    queue.firstUpdate(error); check(first == 11);
    queue.add(&key1, [&] { queue.cancel(&key2); });
    queue.add(&key2, [&] { ++second; });
    queue.firstUpdate(error); check(second == 0);
    queue.add(&key1, [&] { queue.add(&key2, [&] { ++second; }); });
    queue.firstUpdate(error); check(second == 0);
    queue.firstUpdate(error); check(second == 1);
    queue.add(&key1, [] { throw std::runtime_error("expected"); });
    queue.add(&key2, [&] { ++second; });
    queue.firstUpdate(error); queue.firstUpdate(error);
    check(errors == 1 && second == 2);
    std::cout << "PASS: native Loop Start queue lifetime and one-shot checks\n";
}
