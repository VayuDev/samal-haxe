#pragma once

#include <string>
#include <cstdint>
#include <iosfwd>
#include <vector>
#include <memory>
#include <cassert>
#include <type_traits>
#include <iostream>

namespace samalrt {

#ifndef __cpp_unicode_characters
using char32_t = uint32_t;
#endif

class SamalGCTracker;
class SamalContext;
class Datatype;


enum class DatatypeCategory {
    List,
    Int,
    Bool,
    Function,
    Struct,
    Enum
};

static inline size_t alignSize(size_t size) {
    if(size % 8 == 0) {
        return size;
    }
    auto ret = size + (8 - (size % 8));
    assert(ret % 8 == 0);
    assert(ret >= size);
    return ret;
}


class SamalContext final {
public:
    SamalContext();
    ~SamalContext();
    SamalContext(const SamalContext&) = delete;
    SamalContext(SamalContext&&) = delete;
    SamalContext& operator=(const SamalContext&) = delete;
    SamalContext& operator=(SamalContext&&) = delete;

    void setLastGCTracker(SamalGCTracker *last) {
        mLastGCTracker = last;
    }
    SamalGCTracker* getLastGCTracker() {
        return mLastGCTracker;
    }
    void* alloc(size_t len) {
        len = alignSize(len);
        auto ret = mCurrentPage + mCurrentPageOffset;
        mCurrentPageOffset += len;
        assert((uintptr_t)ret % sizeof(void*) == 0);
        return ret;
    }
    void setLambdaCapturedVarPtr(void* ptr) {
        mLambdaCapturedVarPtr = ptr;
    }
    void* getLambdaCapturedVarPtr() {
        return mLambdaCapturedVarPtr;
    }
    void collect();
    void requestCollection();

private:
    SamalGCTracker* mLastGCTracker = nullptr;
    uint8_t* mCurrentPage = nullptr;
    uint8_t* mOtherPage = nullptr;
    size_t mCurrentPageOffset = 0;
    size_t mOtherPageOffset = 0;
    size_t mPageSize = 1024 * 1024 * 1024;
    size_t mCollectionRequestsCounter = 0;
    const size_t mCollectionRequestsPerCollection = 1000000;
    void *mLambdaCapturedVarPtr = nullptr;

    void* allocOnOtherPage(size_t len);
    bool isInOtherPage(void*);
    void visitObj(void *rawPtr, const Datatype& type);
    void* copyToOther(void* rawPtr, size_t size);
};

template<typename FunctionType>
class Function final {
private:
    FunctionType* mFunction;
    std::vector<const Datatype*> mCapturedDatatypes;
    void* mCapturedVariablesBuffer = nullptr;
public:
    Function(FunctionType& function)
    : mFunction(&function) {

    }
    Function() {
        mFunction = nullptr;
    }
    Function& operator=(FunctionType& function) {
        mFunction = &function;
    }
    template<typename ...Args>
    auto operator()(SamalContext& ctx, Args&&... args) -> decltype(mFunction(ctx, args...)) {
        ctx.setLambdaCapturedVarPtr(mCapturedVariablesBuffer);
        return mFunction(ctx, std::forward<Args>(args)...);
    }
    void setCapturedData(void* buffer, std::vector<const Datatype*> capturedDatatypes) {
        mCapturedVariablesBuffer = buffer;
        mCapturedDatatypes = std::move(capturedDatatypes);
    }

    size_t getCapturedVariablesBufferSize();
    
    const std::vector<const Datatype*>& getCapturedTypes() {
        return mCapturedDatatypes;
    }
    void* getCapturedVariablesBuffer() {
        return mCapturedVariablesBuffer;
    }
    // Used for GC
    void setCapturedVariablesBuffer(void* ptr) {
        mCapturedVariablesBuffer = ptr;
    }
};



class Datatype {
public:
    struct FurtherInfoUnion {
        const Datatype* baseType;
        const Datatype* returnType;
        std::vector<const Datatype*> fields;
        std::vector<std::vector<const Datatype*>> variants;
    };
    Datatype(DatatypeCategory category) {
        mCategory = category;
    }
    Datatype(DatatypeCategory category, const Datatype* baseType) {
        mCategory = category;
        mFurtherInfo.baseType = baseType;
    }
    Datatype(DatatypeCategory category, const Datatype* returnType, std::vector<const Datatype*> params) {
        mCategory = category;
        mFurtherInfo.returnType = returnType;
        mFurtherInfo.fields = std::move(params);
    }
    DatatypeCategory getCategory() const {
        return mCategory;
    }
    size_t getSize() const {
        switch(mCategory) {
        case DatatypeCategory::Int:
            return sizeof(int32_t);
        case DatatypeCategory::Bool:
            return sizeof(bool);
        case DatatypeCategory::List:
            return alignSize(sizeof(void*) + mFurtherInfo.baseType->getSize());
        case DatatypeCategory::Function:
            return sizeof(Function<int(int)>);
        case DatatypeCategory::Struct:
            return getSizeOnStack();
        }
        std::cout << static_cast<int>(mCategory) << std::endl;
        assert(false);
    }
    size_t getSizeOnStack() const {
        switch(mCategory) {
        case DatatypeCategory::Int:
            return sizeof(int32_t);
        case DatatypeCategory::Bool:
            return sizeof(bool);
        case DatatypeCategory::List:
            return sizeof(void*);
        case DatatypeCategory::Function:
            return sizeof(Function<int(int)>);
        case DatatypeCategory::Struct: {
            size_t size = 0;
            for(const auto* field: mFurtherInfo.fields) {
                size += field->getSizeOnStack();
            }
            return size;
        }
        case DatatypeCategory::Enum: {
            size_t largestSize = 0;
            for(const auto& variant: mFurtherInfo.variants) {
                size_t size = 0;
                for(const auto* field: variant) {
                    size += field->getSizeOnStack();
                }
                largestSize = std::max(largestSize, size);
            }
            return largestSize + sizeof(int32_t);
        }
        }
        std::cout << static_cast<int>(mCategory) << std::endl;
        assert(false);
    }
    const Datatype& getBaseType() const {
        return *mFurtherInfo.baseType;
    }
    const std::vector<const Datatype*>& getParams() const {
        return mFurtherInfo.fields;
    }
    const std::vector<std::vector<const Datatype*>>& getVariants() const {
        return mFurtherInfo.variants;
    }
private:
    friend class DatatypeStructPlacer;
    friend class DatatypeEnumPlacer;
    DatatypeCategory mCategory;
    FurtherInfoUnion mFurtherInfo;
};

class DatatypeStructPlacer {
public:
    DatatypeStructPlacer(Datatype& structType, size_t index, const Datatype& fieldType) {
        if(structType.mFurtherInfo.fields.size() <= index) {
            structType.mFurtherInfo.fields.resize(index + 1);
        }
        structType.mFurtherInfo.fields.at(index) = &fieldType;
    }
};
class DatatypeEnumPlacer {
public:
    DatatypeEnumPlacer(Datatype& enumType, size_t variant, size_t index, const Datatype& fieldType) {
        if(enumType.mFurtherInfo.variants.size() <= variant) {
            enumType.mFurtherInfo.variants.resize(variant + 1);
        }
        if(enumType.mFurtherInfo.variants.at(variant).size() <= index) {
            enumType.mFurtherInfo.variants.at(variant).resize(index + 1);
        }
        enumType.mFurtherInfo.variants.at(variant).at(index) = &fieldType;
    }
};


template<typename T>
struct List {
    List<T>* next = nullptr;
    T value;
};
template<typename T>
List<T>* listPrepend(SamalContext& ctx, T lhs, List<T>* rhs) {
    List<T>* prev = (List<T>*) ctx.alloc(sizeof(List<T>));
    new(prev)List<T>();
    prev->value = lhs;
    prev->next = rhs;
    return prev;
}
template<typename T>
List<T>* listConcat(SamalContext& ctx, List<T>* lhs, List<T>* rhs) {
    if(lhs == nullptr) {
        return rhs;
    }
    List<T>* current = lhs;
    while(current->next != nullptr) {
        current = current->next;
    }
    current->next = rhs;
    return lhs;
}

using SamalString = List<char32_t>*;


class SamalGCTracker {
public:
    SamalGCTracker(SamalContext& ctx, void *rawPtr, const Datatype& type, bool disableGC = false)
    : mPrev(ctx.getLastGCTracker()), mToTrackRawPtr(rawPtr), mDatatype(type), mCtx(ctx) {
        ctx.setLastGCTracker(this);
        if(!disableGC) {
            ctx.requestCollection();
        }
    }
    ~SamalGCTracker() {
        mCtx.setLastGCTracker(mPrev);
    }

    SamalGCTracker(const SamalGCTracker&) = delete;
    SamalGCTracker& operator=(const SamalGCTracker&) = delete;
    SamalGCTracker(SamalGCTracker&&) = delete;
    SamalGCTracker& operator=(SamalGCTracker&&) = delete;

    SamalGCTracker* getPrev() {
        return mPrev;
    }
    void* getRawPtr() {
        return mToTrackRawPtr;
    }
    const Datatype& getDatatype() {
        return mDatatype;
    }
    
private:
    SamalGCTracker* mPrev = nullptr;
    void* mToTrackRawPtr = nullptr;
    const Datatype& mDatatype;
    SamalContext& mCtx;
};

SamalString toSamalString(SamalContext& ctx, const std::string& str);
SamalString toSamalString(SamalContext& ctx, const std::u32string& str);
SamalString inspect(SamalContext& ctx, int32_t);
SamalString inspect(SamalContext& ctx, bool);

template<typename T>
SamalString inspect(SamalContext& ctx, List<T>* current) {
    std::vector<SamalString> children;
    children.push_back(toSamalString(ctx, "["));
    while(current != nullptr) {
        children.push_back(inspect(ctx, current->value));
        current = current->next;
        if(current) {
            children.push_back(toSamalString(ctx, ", "));
        }
    }
    children.push_back(toSamalString(ctx, "]"));
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