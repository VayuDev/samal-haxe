#include "samal_runtime.hpp"
#include <cstdlib>
#include <string>
#include <codecvt>
#include <locale>
#include <cassert>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace samalrt {


SamalContext::SamalContext() {
    mCurrentPage = (uint8_t*) malloc(mPageSize);
    mOtherPage = (uint8_t*) malloc(mPageSize);
}

SamalContext::~SamalContext() {
    free(mCurrentPage);
    mCurrentPage = nullptr;
    free(mOtherPage);
    mOtherPage = nullptr;
}

SamalString toSamalString(SamalContext& ctx, const std::string& str) {
    std::wstring_convert<std::codecvt_utf8<char32_t>, char32_t> converter;
    auto asInt = converter.from_bytes(str);
    auto u32String = std::u32string(reinterpret_cast<char32_t const *>(asInt.data()), asInt.length());
    return toSamalString(ctx, u32String);
}

SamalString toSamalString(SamalContext& ctx, const std::u32string& str) {
    SamalString head = nullptr;
    for(auto it = str.rbegin(); it != str.rend(); ++it) {
        auto next = (SamalString) ctx.alloc(sizeof(List<char32_t>));
        next->value = *it;
        next->next = head;
        head = next;
    }
    return head;
}

void* SamalContext::allocOnOtherPage(size_t len) {
    len = alignSize(len);
    auto ret = mOtherPage + mOtherPageOffset;
    mOtherPageOffset += len;
    return ret;
}

void SamalContext::requestCollection() {
    mCollectionRequestsCounter += 1;
    if(mCollectionRequestsCounter >= mCollectionRequestsPerCollection) {
        collect();
        mCollectionRequestsCounter = 0;
    }
}

void SamalContext::collect() {
    //std::cout << "Starting collection" << std::endl;
    auto currentRoot = mLastGCTracker;
    while(currentRoot) {
        assert(currentRoot->getRawPtr());
        
        visitObj(currentRoot->getRawPtr(), currentRoot->getDatatype());
        
        currentRoot = currentRoot->getPrev();
    }
    auto tmp = mCurrentPage;
    mCurrentPage = mOtherPage;
    mCurrentPageOffset = mOtherPageOffset;
    mOtherPage = tmp;
    mOtherPageOffset = 0;
    std::cout << "Collected!" << std::endl;
}

void SamalContext::visitObj(void *toVisit, const Datatype& type) {
    assert(toVisit);
    switch(type.getCategory()) {
    case DatatypeCategory::Bool:
    case DatatypeCategory::Int:
        break;
    case DatatypeCategory::List: {
        void** rawPtr = (void**)toVisit;
        while(true) {
            assert((uintptr_t)rawPtr % sizeof(void*) == 0);
            if(*rawPtr == nullptr)
                break;
            if(isInOtherPage(*rawPtr)) {
                break;
            }
            if(isInOtherPage(**(void***)rawPtr)) {
                memcpy(rawPtr, *rawPtr, sizeof(void*));
                break;
            }
            visitObj((void**) ((*(uint8_t***)rawPtr) + 1), type.getBaseType());
            auto newPtr = copyToOther(*rawPtr, type.getSize());
            auto oldPtrToCurrent = *rawPtr;
            memcpy(rawPtr, &newPtr, sizeof(void*));

            rawPtr = *(void***)rawPtr;
            memcpy(oldPtrToCurrent, &newPtr, sizeof(void*));
        }
        break;
    }
    case DatatypeCategory::Function: {
        Function<int(int)>& fn = *(Function<int(int)>*)toVisit;
        if(fn.getCapturedVariablesBuffer() == nullptr) {
            return;
        }
        if(isInOtherPage(fn.getCapturedVariablesBuffer())) {
            return;
        }
        if(isInOtherPage(*(void**)fn.getCapturedVariablesBuffer())) {
            fn.setCapturedVariablesBuffer(*(void**)fn.getCapturedVariablesBuffer());
            return;
        }
        size_t offset = sizeof(void*);
        for(auto capturedType: fn.getCapturedTypes()) {
            visitObj((uint8_t*)fn.getCapturedVariablesBuffer() + offset, *capturedType);
            offset += capturedType->getSizeOnStack();
        }
        void* newPtr = copyToOther(fn.getCapturedVariablesBuffer(), fn.getCapturedVariablesBufferSize());
        memcpy(fn.getCapturedVariablesBuffer(), &newPtr, sizeof(void*));
        fn.setCapturedVariablesBuffer(newPtr);
        memset(newPtr, 0, sizeof(void*));
        break;
    }
    case DatatypeCategory::Struct: {
        auto current = toVisit;
        for(const auto* field: type.getParams()) {
            visitObj(current, *field);
            current = (uint8_t*)current + field->getSizeOnStack();
        }
        break;
    }
    case DatatypeCategory::Enum: {
        int32_t variantIndex = -1;
        memcpy(&variantIndex, toVisit, sizeof(int32_t));
        auto current = (uint8_t*)toVisit + sizeof(int32_t);
        for(const auto* field: type.getVariants().at(variantIndex)) {
            visitObj(current, *field);
            current = (uint8_t*)current + field->getSizeOnStack();
        }
        break;
    }
    default:
        assert(false);
    }
}

template<typename T>
size_t Function<T>::getCapturedVariablesBufferSize() {
    size_t size = sizeof(void*);
    for(auto &d: mCapturedDatatypes) {
        size += d->getSizeOnStack();
    }
    return size;
}



void* SamalContext::copyToOther(void* rawPtr, size_t size) {
    assert(rawPtr);
    auto newPtr = allocOnOtherPage(size);
    memcpy(newPtr, rawPtr, size);
    //std::cout << "Moved " << *rawPtr << " to " << newPtr << std::endl;
    return newPtr;
}

bool SamalContext::isInOtherPage(void* ptr) {
    return ptr >= mOtherPage && ptr < mOtherPage + mOtherPageOffset;
}

SamalString inspect(SamalContext& ctx, int32_t val) {
    auto str = std::to_string(val);
    return toSamalString(ctx, str);
}
SamalString inspect(SamalContext& ctx, bool val) {
    auto str = std::to_string(val);
    return toSamalString(ctx, str);
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