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
// Only Apollo's own image is rebound; other images keep Foundation's
// implementation.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <string.h>

#import "ApolloClasses.h"
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

    // Apollo's executable normally, a dylib under LiveContainer, where the
    // host app is the main executable.
    const char *imageName = ApolloClassPostsViewController ? class_getImageName(ApolloClassPostsViewController) : NULL;
    for (uint32_t i = 0; imageName && i < _dyld_image_count(); i++) {
        const char *candidate = _dyld_get_image_name(i);
        if (!candidate || strcmp(candidate, imageName) != 0) continue;
        rebind_symbols_image((void *)_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i), (struct rebinding[1]){
            {kApolloContainsSymbol, (void *)ApolloFastContains, (void **)&sOriginalContains}
        }, 1);
        ApolloLog(@"[FastStringContains] installed: original=%p", sOriginalContains);
        return;
    }
}
