//
//  PUBPDFDocument.h
//  Publiss
//
//  Copyright (c) 2014 Publiss GmbH. All rights reserved.
//

#import "PSPDFDocument.h"

@class PUBDocument;

@interface PUBPDFDocument : PSPDFDocument

+ (instancetype)documentWithPUBDocument:(PUBDocument *)document;

// Get associated PUBDocument object.
- (PUBDocument *)pubDocument;

// Load annotations.
- (void)loadAnnotationsFromXFDF;

@end
