// Speeds up Foundation's `StringProtocol.contains(_:)` for Apollo's own calls.
//
// Apollo's feed list rebuild (PostsViewController.objects(for:)) checks every
// loaded post's title, flair and URL against every filter keyword with
// `contains`, twice per page load, on the main thread. Foundation compares
// Character by Character there, so the rebuild grows with scroll depth until
// it drops frames. ApolloFastStringContains.swift answers the common
// ASCII-keyword case with a byte search and leaves every other call to
// Foundation.
//
// Only the main executable (Apollo) is rebound; other images keep
// Foundation's implementation.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

#import "ApolloCommon.h"
#import "fishhook.h"

static const char *const kApolloContainsSymbol = "$sSy10FoundationE8containsySbqd__SyRd__lF";

// Swift's generic method convention for `contains<T: StringProtocol>(_ other: T)`
// on a StringProtocol `self`: `other` and `self` are passed indirectly, then the
// metadata and StringProtocol witness tables for Self and T; `self` travels in
// the context register.
typedef __attribute__((swiftcall)) bool (*ApolloContainsFn)(const void *other,
                                                            const void *selfType,
                                                            const void *otherType,
                                                            const void *selfWitness,
                                                            const void *otherWitness,
                                                            __attribute__((swift_context)) const void *self);

extern int32_t ApolloFastContainsDecide(const void *haystack, const void *needle);

static ApolloContainsFn sOriginalContains;
static const void *sStringMetadata;

__attribute__((swiftcall))
static bool ApolloFastContains(const void *other,
                               const void *selfType,
                               const void *otherType,
                               const void *selfWitness,
                               const void *otherWitness,
                               __attribute__((swift_context)) const void *self) {
    if (selfType == sStringMetadata && otherType == sStringMetadata) {
        int32_t decided = ApolloFastContainsDecide(self, other);
        if (decided >= 0) return decided == 1;
    }
    return sOriginalContains(other, selfType, otherType, selfWitness, otherWitness, self);
}

__attribute__((constructor)) static void ApolloFastStringContainsInit(void) {
    sStringMetadata = dlsym(RTLD_DEFAULT, "$sSSN");
    if (!sStringMetadata) return;

    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        if (!header || header->filetype != MH_EXECUTE) continue;
        rebind_symbols_image((void *)header, _dyld_get_image_vmaddr_slide(i), (struct rebinding[1]){
            {kApolloContainsSymbol, (void *)ApolloFastContains, (void **)&sOriginalContains}
        }, 1);
        ApolloLog(@"[FastStringContains] installed: original=%p", sOriginalContains);
        return;
    }
}
