#pragma once

#include <string>
#include <cstdint>
#include <iosfwd>
#include <vector>

namespace samalrt {

#ifndef __cpp_unicode_characters
using char32_t = uint32_t;
#endif

void* samalAlloc(size_t len);

template<typename T>
struct List {
    T value;
    List<T>* next = nullptr;
};

template<typename T>
List<T>* listPrepend(T lhs, List<T>* rhs) {
    List<T>* prev = (List<T>*) samalAlloc(sizeof(List<T>));
    prev->value = lhs;
    prev->next = rhs;
    return prev;
}

using SamalString = List<char32_t>*;

SamalString toSamalString(const std::string& str);
SamalString toSamalString(const std::u32string& str);
SamalString inspect(int32_t);
SamalString inspect(bool);

template<typename T>
SamalString inspect(List<T>* current) {
    std::vector<SamalString> children;
    children.push_back(toSamalString("["));
    while(current != nullptr) {
        children.push_back(inspect(current->value));
        current = current->next;
        if(current) {
            children.push_back(toSamalString(", "));
        }
    }
    children.push_back(toSamalString("]"));
    SamalString ret = nullptr;
    for(auto it = children.rbegin(); it != children.rend(); it++) {
        if(*it == nullptr)
            continue;
        SamalString last = *it;
        while(last->next != nullptr) {
            last = last->next;
        }
        last->next = ret;
        ret = *it;
    }
    return ret;
}

std::ostream& operator<<(std::ostream& stream, SamalString str);

}