//
//  PSPluginExampleSource.m
//  Parsnip2
//
//  Created by Nate Parrott on 12/24/14.
//  Copyright (c) 2014 Nate Parrott. All rights reserved.
//

#import "PSPluginExampleSource.h"
#import "PSHelpers.h"
#import "PSTaggedText+ParseExample.h"
#import "Parsnip.h"

NSString * const PSParsnipSourceDataPluginPathForIntentDictionaryKey = @"PSParsnipSourceDataPluginPathForIntentDictionaryKey";

@interface PSPluginExampleSource ()

@property (nonatomic) dispatch_queue_t fileEventQueue;
@property (nonatomic) dispatch_source_t dispatchSource;
@property (nonatomic,copy) PSParsnipDataCallback dataCallback;

@end

@implementation PSPluginExampleSource

- (instancetype)initWithIdentifier:(NSString *)identifier callback:(PSParsnipDataCallback)callback {
    self = [super initWithIdentifier:identifier callback:callback];
    self.dataCallback = callback;
    [self startWatchingForFileChanges];
    [self didChange];
    return self;
}

- (NSString *)localPluginsPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/FlashlightPlugins"];
}

- (void)startWatchingForFileChanges {
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self localPluginsPath]]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[self localPluginsPath] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    int fileDesc = open([[self localPluginsPath] fileSystemRepresentation], O_EVTONLY);
    
    self.fileEventQueue = dispatch_queue_create("-[PSPluginExampleSource fileEventQueue]", dispatch_queue_attr_make_with_qos_class(0, QOS_CLASS_BACKGROUND, 0));
    // watch the file descriptor for writes
    self.dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fileDesc, DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, self.fileEventQueue);
    
    __weak PSPluginExampleSource *weak_self = self;
    // call the passed block if the source is modified
    dispatch_source_set_event_handler(self.dispatchSource, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weak_self didChange];
        });
    });
    
    // close the file descriptor when the dispatch source is cancelled
    dispatch_source_set_cancel_handler(self.dispatchSource, ^{
        close(fileDesc);
    });
    
    // at this point the dispatch source is paused, so start watching
    dispatch_resume(self.dispatchSource);
}

- (void)reload {
    dispatch_async(self.fileEventQueue, ^{
        [self didChange];
    });
}

- (void)didChange {
    NSMutableArray *parserInfoOutput = [NSMutableArray new];
    NSMutableSet *pathsForPluginsToAlwaysInvoke = [NSMutableSet new];
    
    NSArray *pluginBundles = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self localPluginsPath] error:nil] mapFilter:^id(id obj) {
        NSString *fullPath = [[self localPluginsPath] stringByAppendingPathComponent:obj];
        return [[[fullPath pathExtension] lowercaseString] isEqualToString:@"bundle"] ? fullPath : nil;
    }];
    NSMutableDictionary *pluginPathsForIntents = [NSMutableDictionary new];
    NSMutableArray *examples = [NSMutableArray new];
    for (NSString *pluginPath in pluginBundles) {
        NSString *name = [[pluginPath lastPathComponent] stringByDeletingPathExtension];
        NSString *intentTag = [@"plugin_intent/" stringByAppendingString:name];
        pluginPathsForIntents[intentTag] = pluginPath;
        
        NSString *examplesFilePath = [pluginPath stringByAppendingPathComponent:@"examples.txt"];
        for (NSString *line in [[[NSString alloc] initWithContentsOfFile:examplesFilePath usedEncoding:nil error:nil] componentsSeparatedByString:@"\n"]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length) {
                if ([trimmed.lowercaseString isEqualToString:@"!always_invoke"]) {
                    [pathsForPluginsToAlwaysInvoke addObject:pluginPath];
                } else {
                    PSTaggedText *example = [PSTaggedText withExampleString:trimmed rootTag:intentTag];
                    if (example) {
                        [examples addObject:example];
                    } else {
                        // parse failed:
                        [parserInfoOutput addObject:[NSString stringWithFormat:@"%@.bundle/examples.txt error:\nExample '%@' is invalid.", name, line]];
                    }
                }
            }
        }
    }
    
    Parsnip *ps = [Parsnip new];
    [ps learnExamples:examples];
    
    NSArray *nullExamples = @[
                              @"~rheighiotrggoeg(orhgouergneripg)",
                              @"this is gibberish 98rhgpeogierg",
                              @"rhger rehgoerh grghegoi?",
                              @"what righei gheriogjerigp eeroguhegio",
                              @"a the it",
                              @"where who ?",
                              @"the : to",
                              @""
                              ];
    NSInteger i = 0;
    for (NSString *ex in nullExamples) {
        NSString *tag = [NSString stringWithFormat:@"plugin_intent/null_%li", (long)i++];
        [ps learnExamples:@[[PSTaggedText withExampleString:ex rootTag:tag]]];
        [ps setLogProbBoost:1 forTag:tag];
    }
    
    NSDictionary *data = @{
                           PSParsnipSourceDataParsnipKey: ps,
                           PSParsnipSourceDataPluginPathForIntentDictionaryKey: pluginPathsForIntents
                           };
    self.dataCallback(self.identifier, data);
    
    self.parserInfoOutput = [parserInfoOutput componentsJoinedByString:@"\n\n"];
    if (self.parserOutputChangedBlock) self.parserOutputChangedBlock();
    self.pathsOfPluginsToAlwaysInvoke = pathsForPluginsToAlwaysInvoke;
}

- (void)dealloc {
    dispatch_source_cancel(self.dispatchSource);
}

@end
