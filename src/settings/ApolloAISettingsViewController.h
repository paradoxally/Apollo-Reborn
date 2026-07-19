#import "ApolloSettingsForm.h"

// "Apollo AI" sub-screen pushed from the tweak settings: master Enable Apollo
// AI switch, the Summaries toggles (Tap to Summarize and Open Summaries
// Automatically are alternatives — each greys the other out), the Cloud Model
// configuration (BYOK OpenAI-compatible backend with save-on-blur fields),
// on-device and cloud model availability status rows, and cache/log
// maintenance actions. Declarative form — see -buildForm.
@interface ApolloAISettingsViewController : ApolloSettingsFormViewController <UITextFieldDelegate>
@end
