#pragma once

#include <string>
#include <cstdint>
#include <iosfwd>
#include <vector>
#include <memory>
#include <cassert>

namespace samalrt {

#ifndef __cpp_unicode_characters
using char32_t = uint32_t;
#endif

class SamalGCTracker;
class SamalContext;


enum class DatatypeCategory {
    List,
    Int,
    Bool
};

static inline size_t alignSize(size_t size) {
    if(size % 8 == 0) {
        return size;
    }
    return size + (8 - size % 8);
}

class Datatype {
public:
    union FurtherInfoUnion {
        const Datatype* baseType;
    };
    Datatype(DatatypeCategory category) {
        mCategory = category;
    }
    Datatype(DatatypeCategory category, const Datatype* baseType) {
        mCategory = category;
        mFurtherInfo.baseType = baseType;
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
        }
        assert(false);
    }
    const Datatype& getBaseType() const {
        return *mFurtherInfo.baseType;
    }
private:
    DatatypeCategory mCategory;
    FurtherInfoUnion mFurtherInfo;
};


class SamalContext {
public:
    SamalContext();
    void setLastGCTracker(SamalGCTracker& last) {
        mLastGCTracker = &last;
    }
    SamalGCTracker* getLastGCTracker() {
        return mLastGCTracker;
    }
    void* alloc(size_t len) {
        len = alignSize(len);
        auto ret = mCurrentPage + mCurrentPageOffset;
        mCurrentPageOffset += len;
        return ret;
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
    const size_t mCollectionRequestsPerCollection = 10000;

    void* allocOnOtherPage(size_t len);
    bool isInOtherPage(void*);
    void visitObj(void *rawPtr, const Datatype& type);
    void* copyToOther(void** rawPtr, size_t size);
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

using SamalString = List<char32_t>*;


class SamalGCTracker {
public:
    SamalGCTracker(SamalContext& ctx, void *rawPtr, Datatype type)
    : mPrev(ctx.getLastGCTracker()), mToTrackRawPtr(rawPtr), mDatatype(type), mCtx(ctx) {
        ctx.setLastGCTracker(*this);
        ctx.requestCollection();
    }
    ~SamalGCTracker() {
        mCtx.setLastGCTracker(*mPrev);
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
    Datatype mDatatype;
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


namespace samalds {

using namespace samalrt;

static Datatype int_{DatatypeCategory::Int};
static Datatype bool_{DatatypeCategory::Bool};
static Datatype list_sint_e{DatatypeCategory::List, &int_};

}