#pragma once

#include <string>
#include <cstdint>
#include <iosfwd>

namespace samalrt {

#ifndef __cpp_unicode_characters
using char32_t = uint32_t;
#endif

template<typename T>
struct List {
    T value;
    List<T>* next = nullptr;
};

using SamalString = List<char32_t>*;

SamalString toSamalString(const std::string& str);
SamalString toSamalString(const std::u32string& str);
SamalString inspect(int32_t);
SamalString inspect(bool);

void* samalAlloc(size_t len);

std::ostream& operator<<(std::ostream& stream, SamalString str);

}