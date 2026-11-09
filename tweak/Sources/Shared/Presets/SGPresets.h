#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

// A saved snapshot of the appearance (accent, AMOLED, redesign accent) the user
// can name and re-apply. Stored under spotifyglass.presets so the backup keeps
// it. One row, added to both looks' Appearance cards, opens the manager.
SGModRow *SGPresetsRow(void);
