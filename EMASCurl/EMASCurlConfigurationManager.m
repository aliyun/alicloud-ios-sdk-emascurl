//
//  EMASCurlConfigurationManager.m
//  EMASCurl
//
//  Created by EMASCurl on 2025/01/02.
//

#import "EMASCurlConfigurationManager.h"
#import "EMASCurlLogger.h"

@interface EMASCurlConfigurationManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, EMASCurlConfiguration *> *configurations;
@property (nonatomic, strong) EMASCurlConfiguration *defaultConfiguration;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation EMASCurlConfigurationManager

@synthesize defaultConfiguration = _defaultConfiguration;

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static EMASCurlConfigurationManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[EMASCurlConfigurationManager alloc] init];
    });
    return manager;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _configurations = [NSMutableDictionary new];
        _defaultConfiguration = [EMASCurlConfiguration defaultConfiguration];
        _queue = dispatch_queue_create("com.emas.curl.config.manager", DISPATCH_QUEUE_CONCURRENT);

        EMAS_LOG_INFO(@"EC-ConfigManager", @"Configuration manager initialized");
    }
    return self;
}

#pragma mark - Configuration Management

- (void)setConfiguration:(EMASCurlConfiguration *)configuration forID:(NSString *)configID {
    if (!configuration || !configID) {
        EMAS_LOG_ERROR(@"EC-ConfigManager", @"Cannot set configuration: nil configuration or ID");
        return;
    }

    dispatch_barrier_async(self.queue, ^{
        self.configurations[configID] = configuration;
        EMAS_LOG_DEBUG(@"EC-ConfigManager", @"Stored configuration for ID: %@", configID);
    });
}

- (nullable EMASCurlConfiguration *)configurationForID:(NSString *)configID {
    if (!configID) {
        EMAS_LOG_DEBUG(@"EC-ConfigManager", @"Cannot get configuration: nil ID");
        return nil;
    }

    __block EMASCurlConfiguration *config = nil;
    dispatch_sync(self.queue, ^{
        config = self.configurations[configID];
    });

    if (!config) {
        EMAS_LOG_DEBUG(@"EC-ConfigManager", @"Configuration not found for ID: %@", configID);
    }

    return config;
}

- (void)removeConfigurationForID:(NSString *)configID {
    if (!configID) {
        EMAS_LOG_DEBUG(@"EC-ConfigManager", @"Cannot remove configuration: nil ID");
        return;
    }

    dispatch_barrier_async(self.queue, ^{
        [self.configurations removeObjectForKey:configID];
        EMAS_LOG_DEBUG(@"EC-ConfigManager", @"Removed configuration for ID: %@", configID);
    });
}

- (void)removeAllConfigurations {
    dispatch_barrier_async(self.queue, ^{
        [self.configurations removeAllObjects];
        EMAS_LOG_INFO(@"EC-ConfigManager", @"Removed all configurations");
    });
}

- (NSArray<NSString *> *)allConfigurationIDs {
    __block NSArray<NSString *> *ids = nil;
    dispatch_sync(self.queue, ^{
        ids = [self.configurations allKeys];
    });
    return ids ?: @[];
}

#pragma mark - Default Configuration

- (EMASCurlConfiguration *)defaultConfiguration {
    __block EMASCurlConfiguration *config = nil;
    dispatch_sync(self.queue, ^{
        config = _defaultConfiguration;
    });
    return config ?: [EMASCurlConfiguration defaultConfiguration];
}

- (void)setDefaultConfiguration:(EMASCurlConfiguration *)configuration {
    if (!configuration) {
        EMAS_LOG_ERROR(@"EC-ConfigManager", @"Cannot set nil as default configuration");
        return;
    }

    dispatch_barrier_async(self.queue, ^{
        self->_defaultConfiguration = configuration;
        EMAS_LOG_INFO(@"EC-ConfigManager", @"Updated default configuration");
    });
}

#pragma mark - Debug

- (NSString *)description {
    __block NSUInteger count = 0;
    dispatch_sync(self.queue, ^{
        count = self.configurations.count;
    });

    return [NSString stringWithFormat:@"<%@: %p, configurations=%lu>",
            NSStringFromClass([self class]),
            self,
            (unsigned long)count];
}

@end
