#include "samal_runtime.hpp"
#include <cstdlib>
#include <string>
#include <codecvt>
#include <locale>

namespace samalrt {

SamalString toSamalString(const std::string& str) {
    std::wstring_convert<std::codecvt_utf8<char32_t>, char32_t> converter;
    auto asInt = converter.from_bytes(str);
    auto u32String = std::u32string(reinterpret_cast<char32_t const *>(asInt.data()), asInt.length());
    return toSamalString(u32String);
}

SamalString toSamalString(const std::u32string& str) {
    SamalString head = nullptr;
    for(auto it = str.rbegin(); it != str.rend(); ++it) {
        auto next = (SamalString) samalAlloc(sizeof(List<char32_t>));
        next->value = *it;
        next->next = head;
        head = next;
    }
    return head;
}
void* samalAlloc(size_t len) {
    return malloc(len);
}

SamalString inspect(int32_t val) {
    auto str = std::to_string(val);
    return toSamalString(str);
}
SamalString inspect(bool val) {
    auto str = std::to_string(val);
    return toSamalString(str);
}

std::ostream& operator<<(std::ostream& stream, SamalString str) {
    std::wstring_convert<std::codecvt_utf8<char32_t>, char32_t> converter;
    auto current = str;
    while(current) {
        stream << converter.to_bytes(&current->value, &current->value + 1);
        current = current->next;
    }
    return stream;
}

}