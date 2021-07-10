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
            if(*rawPtr == nullptr)
                break;
            if(isInOtherPage(*rawPtr)) {
                break;
            }
            if(isInOtherPage(**(void***)rawPtr)) {
                *rawPtr = **(void***)rawPtr;
                break;
            }
            visitObj((void**) (*(uint8_t***)rawPtr + 8), type.getBaseType());
            auto newPtr = copyToOther(*rawPtr, type.getSize());
            auto oldPtrToCurrent = *rawPtr;
            *rawPtr = newPtr;

            rawPtr = *(void***)rawPtr;
            *(void**)oldPtrToCurrent = newPtr;
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
        break;
    }
    }
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