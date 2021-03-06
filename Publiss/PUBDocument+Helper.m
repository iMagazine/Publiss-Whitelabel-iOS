//
//  PUBDocument+Helper.m
//  Publiss
//
//  Copyright (c) 2014 Publiss GmbH. All rights reserved.
//

#import "PUBDocument+Helper.h"
#import "PUBAppDelegate.h"
#import "PUBPDFDocument.h"
#import <Lockbox/Lockbox.h>
#import "PUBThumbnailImageCache.h"

@implementation PUBDocument (Helper)

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p \"%@\" size = %llu, productID = %@, state = %tu>.", self.class, self, self.title, self.size, self.productID, self.state];
}

#pragma mark - data model helpers

+ (PUBDocument *)createEntity {
    PUBAppDelegate *appDelegate = UIApplication.sharedApplication.delegate;
    PUBDocument *newEntity = [NSEntityDescription insertNewObjectForEntityForName:@"PUBDocument"
                                                           inManagedObjectContext:appDelegate.managedObjectContext];

    return newEntity;
}

+ (PUBDocument *)createPUBDocumentWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class] || dictionary.count == 0) {
        PUBLogWarning(@"Dictionary is empty.");
        return nil;
    }

    BOOL shouldUpdateValues = NO;
    PUBDocument *document = [PUBDocument findExistingPUBDocumentWithProductID:dictionary[@"apple_product_id"]];
    if (!document) {
        document = [PUBDocument createEntity];
        shouldUpdateValues = YES;
    } else {
        shouldUpdateValues = ![document.updatedAt isEqual:dictionary[@"updated_at"]];
    }

    static NSDateFormatter *_dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        _dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });

    if (shouldUpdateValues) {
        // Never trust external content.
        @try {
            document.productID = PUBSafeCast(dictionary[@"apple_product_id"], NSString.class);
            document.publishedID = (uint16_t)[dictionary[@"id"] integerValue];
            document.updatedAt = [_dateFormatter dateFromString:PUBSafeCast(dictionary[@"updated_at"], NSString.class)];
            document.priority = (uint16_t)[dictionary[@"priority"] integerValue];
            document.title = PUBSafeCast(dictionary[@"name"], NSString.class);
            document.pageCount = (uint16_t)[[dictionary valueForKeyPath:@"pages_info.count"] integerValue] - 1;
            document.fileDescription = PUBSafeCast(dictionary[@"description"], NSString.class);
            document.paid = [[dictionary valueForKeyPath:@"paid"] boolValue];
            document.fileSize = (uint64_t) [dictionary[@"file_size"] longLongValue];

            // Progressive download support
            document.sizes = PUBSafeCast([dictionary valueForKeyPath:@"pages_info.sizes"], NSArray.class);
            document.dimensions = PUBSafeCast([dictionary valueForKeyPath:@"pages_info.dimensions"], NSArray.class);
        }
        @catch (NSException *exception) {
            PUBLogError(@"Exception while parsing JSON: %@", exception);
        }
    }

    [document importValuesFromDictionaty:dictionary];
    return document;
}

- (void)importValuesFromDictionaty:(NSDictionary *)dict {
    NSDictionary *attributes = self.entity.attributesByName;

    for (NSString *key in attributes.allKeys) {
        if ([dict.allKeys containsObject:key]) {
            [self setValue:dict[key] forKey:key];
        }
    }
}

+ (PUBDocument *)findExistingPUBDocumentWithProductID:(NSString *)productID {
    PUBAppDelegate *appDelegate = (PUBAppDelegate *) UIApplication.sharedApplication.delegate;

    NSFetchRequest *fetchRequest = [NSFetchRequest new];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"productID = %@", productID];
    fetchRequest.entity = [self getEntity];

    NSArray *fetchedResults = [appDelegate.managedObjectContext executeFetchRequest:fetchRequest error:NULL];
    return fetchedResults.firstObject;
}

+ (NSArray *)findAll {
    return [self findWithPredicate:nil];
}

+ (NSFetchedResultsController *)fetchAllSortedBy:(NSString *)sortKey ascending:(BOOL)ascending {
    PUBAppDelegate *appDelegate = (PUBAppDelegate *) UIApplication.sharedApplication.delegate;

    NSFetchRequest *fetchRequest = [NSFetchRequest new];
    fetchRequest.entity = [self getEntity];

    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:sortKey ascending:ascending];
    fetchRequest.sortDescriptors = @[sortDescriptor];

    NSFetchedResultsController *controller =
    [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                        managedObjectContext:appDelegate.managedObjectContext
                                          sectionNameKeyPath:nil
                                                   cacheName:nil];

    NSError *error = nil;
    if (![controller performFetch:&error]) {
        PUBLogError(@"Error while fetching documents: %@", error);
    }

    return controller;
}

+ (NSArray *)findWithPredicate:(NSPredicate *)predicate {
    PUBAppDelegate *appDelegate = (PUBAppDelegate *) UIApplication.sharedApplication.delegate;

    NSFetchRequest *fetchRequest = [NSFetchRequest new];
    fetchRequest.predicate = predicate;
    fetchRequest.entity = [self getEntity];
    return [appDelegate.managedObjectContext executeFetchRequest:fetchRequest error:NULL];
}

+ (NSEntityDescription *)getEntity {
    PUBAppDelegate *appDelegate = (PUBAppDelegate *) UIApplication.sharedApplication.delegate;
    return [NSEntityDescription entityForName:@"PUBDocument" inManagedObjectContext:appDelegate.managedObjectContext];
}

- (void)deleteEntity {
    [self.managedObjectContext deleteObject:self];
}

- (NSURL *)localDocumentURL {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

    NSError *error;
    NSString *publissPath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"publiss/%@", self.productID]];
    NSFileManager *fileManager = [NSFileManager new];
    if (![fileManager fileExistsAtPath:publissPath]) {
        if (![fileManager createDirectoryAtPath:publissPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            PUBLogError(@"Failed to create dir: %@", error.localizedDescription);
        }
    }
    return [NSURL fileURLWithPath:publissPath];
}

- (NSURL *)localDocumentURLForPage:(NSUInteger)page {
    return [self.localDocumentURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%tu.pdf", page] isDirectory:NO];
}

+ (void)restoreDocuments {
    for (PUBDocument *document in [PUBDocument findAll]) {
        if (document.state == PUBDocumentStateLoading) {
            document.state = PUBDocumentStateOnline;
        }
    }
}

#pragma mark helper method

- (void)deleteDocument:(void (^)())completionBlock {
    if ([self.productID length]) {
        PUBDocument *document = self;
        
        NSError *clearCacheError = nil;
        NSError *error = nil;
        if (document && document.state == PUBDocumentStateDownloaded) {
            // remove pdf cache for document
            if ([PSPDFCache.sharedCache removeCacheForDocument:[PUBPDFDocument documentWithPUBDocument:document] deleteDocument:YES error:&clearCacheError]) {
                PUBLogVerbose(@"PDF Cache for document %@ cleared.", document.title);
            } else {
                PUBLogError(@"Error clearing PDF Cache for document %@: %@", document.title, clearCacheError.localizedDescription);
            }
            
            // remove last view state
            if ([document removedLastViewState]) {
                PUBLogVerbose(@"Last ViewState with document %@ removed.", document.title);
            }
            
            
            if ([NSFileManager.defaultManager removeItemAtURL:document.localDocumentURL error:&error]) {
                PUBLogVerbose(@"Deleted Document from filesystem: %@", document.title);
            } else {
                PUBLogWarning(@"Error deleting document from filesystem: %@", error.localizedDescription);
            }
            
            
            if ([NSFileManager.defaultManager removeItemAtURL:document.localXFDFURL error:&error]) {
                PUBLogVerbose(@"Deleted Document XFDF from filesystem URL: %@", document.localXFDFURL);
            } else {
                PUBLogWarning(@"Error deleting XFDF from filesystem: %@", error.localizedDescription);
            }
            
            document.state = PUBDocumentStateOnline;
            [(PUBAppDelegate *)UIApplication.sharedApplication.delegate saveContext];
            if (completionBlock) completionBlock();
        }
    }
}

+ (void)deleteAll {
    for (PUBDocument *document in [PUBDocument findAll]) {
        [document deleteDocument:NULL];
    }
    [PSPDFCache.sharedCache clearCache];
    [PUBThumbnailImageCache.sharedInstance clearCache];
    [(PUBAppDelegate *)UIApplication.sharedApplication.delegate saveContext];
}

- (NSURL *)localXFDFURL {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.xfdf", self.productID]];
    NSURL *fileXML = [NSURL fileURLWithPath:path];
    return fileXML;
}

- (NSString *)iapSecret {
    return [[Lockbox dictionaryForKey:PUBiAPSecrets] objectForKey:self.productID];
}

#pragma mark - PSPDFKit Viewstate

- (PSPDFViewState *)lastViewState {
    PSPDFViewState *viewState = nil;

    NSData *viewStateData = [NSUserDefaults.standardUserDefaults objectForKey:[NSString stringWithFormat:@"@%@", self.productID]];
    @try {
        if (viewStateData) {
            viewState = [NSKeyedUnarchiver unarchiveObjectWithData:viewStateData];
        }
    }
    @catch (NSException *exception) {
        PUBLogError(@"Failed to load saved viewState: %@", exception);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[NSString stringWithFormat:@"@%@", self.productID]];
    }
    return viewState;
}

- (void)setLastViewState:(PSPDFViewState *)lastViewState {
    if (lastViewState) {
        NSData *viewStateData = [NSKeyedArchiver archivedDataWithRootObject:lastViewState];
        [NSUserDefaults.standardUserDefaults setObject:viewStateData
                                                forKey:[NSString stringWithFormat:@"@%@", self.productID]];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[NSString stringWithFormat:@"@%@", self.productID]];
    }
}

- (BOOL)removedLastViewState {
    NSData *viewStateData = [NSUserDefaults.standardUserDefaults objectForKey:[NSString stringWithFormat:@"@%@", self.productID]];
    
    if (viewStateData) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[NSString stringWithFormat:@"@%@", self.productID]];
        return YES;
    }
    return NO;
}

#pragma mark - Data Wrappers

- (NSArray *)sizes {
    return [NSKeyedUnarchiver unarchiveObjectWithData:self.sizesData];
}

- (void)setSizes:(NSArray *)sizes {
    self.sizesData = [NSKeyedArchiver archivedDataWithRootObject:sizes];
}

- (NSArray *)dimensions {
    return [NSKeyedUnarchiver unarchiveObjectWithData:self.dimensionsData];
}

- (void)setDimensions:(NSArray *)dimensions {
    self.dimensionsData = [NSKeyedArchiver archivedDataWithRootObject:dimensions];
}

@end
