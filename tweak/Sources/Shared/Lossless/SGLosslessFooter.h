// The mod's rows under Spotify's context menu: a box that is the menu table's footer, its rows stacked in
// the order of their tags (1 Download lossless, 2 Playlist Fusion). Each row's owner calls this on every
// layout pass of the menu, so the rows come back when Spotify replaces the footer or the table changes width.
#import <UIKit/UIKit.h>

static NSString *const kSGLosslessFooterID = @"SGLosslessFooter";

// NO when Spotify has a footer of its own there, which is left alone.
static inline BOOL SGLosslessFooterPlace(UITableView *table, UIControl *row, CGFloat width, CGFloat rowHeight) {
    UIView *box = row.superview;
    if (![box.accessibilityIdentifier isEqualToString:kSGLosslessFooterID]) {
        UIView *footer = table.tableFooterView;
        if ([footer.accessibilityIdentifier isEqualToString:kSGLosslessFooterID]) {
            box = footer;
        } else if (!footer || footer.bounds.size.height < 1) {
            box = [UIView new];
            box.accessibilityIdentifier = kSGLosslessFooterID;
            box.backgroundColor = UIColor.clearColor;
        } else {
            return NO;
        }
        [box addSubview:row];
    }
    NSArray<UIView *> *rows = [box.subviews sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.tag < b.tag ? NSOrderedAscending : a.tag > b.tag ? NSOrderedDescending : NSOrderedSame;
    }];
    CGFloat y = 0;
    for (UIView *each in rows) {
        CGRect frame = CGRectMake(0, y, width, rowHeight);
        if (!CGRectEqualToRect(each.frame, frame)) each.frame = frame;
        y += rowHeight;
    }
    BOOL changed = table.tableFooterView != box ||
        fabs(box.frame.size.width - width) > 0.5 || fabs(box.frame.size.height - y) > 0.5;
    if (changed) {
        box.frame = CGRectMake(0, 0, width, y);
        table.tableFooterView = box;
        [table invalidateIntrinsicContentSize];
    }
    return YES;
}
