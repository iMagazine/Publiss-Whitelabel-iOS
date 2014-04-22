//
//  PUBPagePreviewViewController.m
//  Publiss
//
//  Copyright (c) 2014 Publiss GmbH. All rights reserved.
//

#import "PUBPagePreviewViewController.h"
#import "PUBPreviewCell.h"
#import "PUBCenteredScrollView.h"
#import "UIColor+Design.h"
#import "PUBDocumentFetcher.h"
#import "PUBDocument.h"
#import "UIImageView+AFNetworking.h"
#import "PUBThumbnailImageCache.h"
#import "PUBURLFactory.h"

@interface PUBPagePreviewViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, assign) NSInteger currentIndex;
@end

@implementation PUBPagePreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    UIApplication.sharedApplication.statusBarStyle = UIStatusBarStyleLightContent;
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissNavController:)];
    doneButton.tintColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItems = @[ doneButton ];
    
    self.navigationController.navigationItem.title = self.pageName;
    self.navigationController.navigationBar.barTintColor = [UIColor publissPrimaryColor];

    [self setupCollectionView];
    [self setupBackgroundBlur];
    [self setupGestureRecognizers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showPage:self.initialPage];
    [self updateTitle];
}

- (void)viewWillDisappear:(BOOL)animated {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setupGestureRecognizers {
    UITapGestureRecognizer *doubleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self.view addGestureRecognizer:singleTap];
}

- (void)tapped:(UITapGestureRecognizer *)tapGesture {
    if (tapGesture.state == UIGestureRecognizerStateEnded) {
        [self.navigationController setNavigationBarHidden:!self.navigationController.navigationBarHidden animated:YES];
    }
}

- (void)doubleTapped:(UITapGestureRecognizer *)tapGesture {
    CGPoint locationInCollectionView = [tapGesture locationInView:self.view];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:locationInCollectionView];
    PUBPreviewCell *cell = (PUBPreviewCell *)[self.collectionView cellForItemAtIndexPath:indexPath];

    if (cell != nil) {
        CGPoint locationInScrollView = [tapGesture locationInView:cell.scrollView];
        [cell.scrollView zoomAtPoint:locationInScrollView];
    }
}

- (void)setupCollectionView {
    [self.collectionView registerClass:PUBPreviewCell.class forCellWithReuseIdentifier:@"cellIdentifier"];

    UICollectionViewFlowLayout *flowLayout = UICollectionViewFlowLayout.alloc.init;
    flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    flowLayout.minimumInteritemSpacing = 0.0f;
    flowLayout.minimumLineSpacing = 0.0f;
    self.collectionView.pagingEnabled = YES;
    self.collectionView.collectionViewLayout = flowLayout;
    self.collectionView.backgroundColor = UIColor.clearColor;
}

- (void)dismissNavController:(id)sender {
    if ([sender isKindOfClass:UIBarButtonItem.class]) {
        if (!self.presentingViewController.isBeingPresented) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }
}

- (void)setupBackgroundBlur {
    CGRect frame =
    CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame));
    UINavigationBar *translucentView = [[UINavigationBar alloc] initWithFrame:frame];
     translucentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.collectionView.superview addSubview:translucentView];
    [self.collectionView.superview sendSubviewToBack:translucentView];
    translucentView.backgroundColor = UIColor.clearColor;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                duration:(NSTimeInterval)duration {
    CGPoint currentOffset = self.collectionView.contentOffset;
    self.currentIndex = (NSInteger)(currentOffset.x / self.collectionView.bounds.size.width);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self.collectionView.collectionViewLayout invalidateLayout];

    CGSize currentSize = self.collectionView.bounds.size;
    CGFloat offset = self.currentIndex * currentSize.width;
    [self.collectionView setContentOffset:CGPointMake(offset, 0)];
}

- (void)showPage:(NSInteger)page {
    [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:page inSection:0]
                                atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                        animated:NO];
}

#pragma mark UICollectionViewDelegate

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return MIN(5, self.document.pageCount + 1);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PUBPreviewCell *cell = (PUBPreviewCell *)
        [collectionView dequeueReusableCellWithReuseIdentifier:@"cellIdentifier" forIndexPath:indexPath];
    
    NSString *previewImageURL = [PUBURLFactory createPreviewImageURLStringForDocument:self.document.publishedID page:indexPath.row];
    
    PUBPreviewCell *weakCell = cell;
    NSURLRequest *urlrequest = [NSURLRequest requestWithURL:[NSURL URLWithString:previewImageURL]];
    
    if ([PUBThumbnailImageCache.sharedInstance thumbnailImageWithURLString:previewImageURL]) {
        cell.previewImageView.image = [PUBThumbnailImageCache.sharedInstance thumbnailImageWithURLString:previewImageURL];
        [cell setNeedsDisplay];
    } else {
        [weakCell.activityIndicator startAnimating];
        [cell.previewImageView setImageWithURLRequest:urlrequest
                                 placeholderImage:nil
                                          success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
                                              [PUBThumbnailImageCache.sharedInstance setImage:image forURLString:previewImageURL];
                                              [UIView transitionWithView:weakCell.previewImageView
                                                                duration:0.35f
                                                                 options:UIViewAnimationOptionTransitionCrossDissolve
                                                              animations:^{ weakCell.previewImageView.image = image; }
                                                              completion:^(BOOL finished){
                                                                  [weakCell.activityIndicator stopAnimating];
                                                                  [weakCell setNeedsDisplay];
                                                              }];
                                          } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
                                              PUBLogError(@"%@: Error fetching Previewimage URL, %@", [self class], error.localizedDescription);
                                              [weakCell.activityIndicator stopAnimating];
                                          }];
    }

    [cell enableZooming];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.collectionView.bounds.size;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    static NSInteger previousPage = 0;
    NSInteger page = self.currentPage;
    if (previousPage != page) {
        previousPage = page;
        [self updateTitle];
    }
}

- (NSInteger)currentPage {
    CGFloat pageWidth = self.collectionView.frame.size.width;
    CGFloat fractionalPage = self.collectionView.contentOffset.x / pageWidth;
    return lround(fractionalPage);
}

- (void)updateTitle {
    self.navigationItem.title =
        [NSString stringWithFormat:PUBLocalize(@"Preview Page %d of %d"), self.currentPage + 1, MIN(5,self.document.pageCount + 1)];
     self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
}

@end