//
//  EMASCurlConfiguration.m
//  EMASCurl
//
//  Created by assistant on 2025/07/12.
//

#import "EMASCurlConfiguration.h"
#import "EMASCurlProtocol.h"

@implementation EMASCurlConfiguration

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _httpVersion = HTTP2;
        _builtInGzipEnabled = YES;
        _builtInRedirectionEnabled = YES;
        _certificateValidationEnabled = YES;
        _domainNameVerificationEnabled = YES;
        _cacheEnabled = YES;
    }
    return self;
}

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    EMASCurlConfiguration *copy = [[EMASCurlConfiguration alloc] init];
    
    copy.httpVersion = self.httpVersion;
    copy.builtInGzipEnabled = self.builtInGzipEnabled;
    copy.builtInRedirectionEnabled = self.builtInRedirectionEnabled;
    copy.selfSignedCAFilePath = [self.selfSignedCAFilePath copy];
    copy.certificateValidationEnabled = self.certificateValidationEnabled;
    copy.domainNameVerificationEnabled = self.domainNameVerificationEnabled;
    copy.publicKeyPinningKeyPath = [self.publicKeyPinningKeyPath copy];
    copy.dnsResolverClass = self.dnsResolverClass;
    copy.manualProxyServer = [self.manualProxyServer copy];
    copy.hijackDomainWhiteList = [self.hijackDomainWhiteList copy];
    copy.hijackDomainBlackList = [self.hijackDomainBlackList copy];
    copy.cacheEnabled = self.cacheEnabled;

    return copy;
}

#pragma mark - Convenience Methods

- (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver {
    self.dnsResolverClass = dnsResolver;
}

#pragma mark - Description

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> {\n"
            @"  httpVersion: %ld\n"
            @"  builtInGzipEnabled: %@\n"
            @"  builtInRedirectionEnabled: %@\n"
            @"  certificateValidationEnabled: %@\n"
            @"  domainNameVerificationEnabled: %@\n"
            @"  cacheEnabled: %@\n"
            @"  dnsResolverClass: %@\n"
            @"  hijackDomainWhiteList: %@\n"
            @"  hijackDomainBlackList: %@\n"
            @"}",
            NSStringFromClass([self class]), self,
            (long)self.httpVersion,
            self.builtInGzipEnabled ? @"YES" : @"NO",
            self.builtInRedirectionEnabled ? @"YES" : @"NO",
            self.certificateValidationEnabled ? @"YES" : @"NO",
            self.domainNameVerificationEnabled ? @"YES" : @"NO",
            self.cacheEnabled ? @"YES" : @"NO",
            self.dnsResolverClass,
            self.hijackDomainWhiteList,
            self.hijackDomainBlackList];
}

@end
