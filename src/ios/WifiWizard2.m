#import "WifiWizard2.h"
#include <ifaddrs.h>
#import <net/if.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <NetworkExtension/NetworkExtension.h>
#import <NetworkExtension/NEHotspotNetwork.h>

@implementation WifiWizard2

- (void)fetchSSIDInfoWithCompletion:(void (^)(NSDictionary *))completion {
    if (@available(iOS 14.0, *)) {
        [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
            NSDictionary *info;
            if (currentNetwork) {
                info = @{(id)kCNNetworkInfoKeySSID: [currentNetwork SSID],
                    (id)kCNNetworkInfoKeyBSSID: [currentNetwork BSSID]};
            } else {
                info = @{};
            }
            completion(info);
        }];
    } else {
        NSArray *ifs = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
        NSDictionary *info;
        for (NSString *ifnam in ifs) {
            info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
            if (info && [info count]) { break; }
        }
        completion(info);
    }
}

- (BOOL) isWiFiEnabled {
    // see http://www.enigmaticape.com/blog/determine-wifi-enabled-ios-one-weird-trick
    NSCountedSet * cset = [NSCountedSet new];

    struct ifaddrs *interfaces = NULL;
    // retrieve the current interfaces - returns 0 on success
    int success = getifaddrs(&interfaces);
    if(success == 0){
        for( struct ifaddrs *interface = interfaces; interface; interface = interface->ifa_next) {
            if ( (interface->ifa_flags & IFF_UP) == IFF_UP ) {
                [cset addObject:[NSString stringWithUTF8String:interface->ifa_name]];
            }
        }
    }

    return [cset countForObject:@"awdl0"] > 1 ? YES : NO;
}

- (void)iOSConnectNetwork:(CDVInvokedUrlCommand*)command {
    
  __block CDVPluginResult *pluginResult = nil;

  NSString * ssidString;
  NSString * passwordString;
  NSDictionary* options = [[NSDictionary alloc]init];

  options = [command argumentAtIndex:0];
  ssidString = [options objectForKey:@"Ssid"];
  passwordString = [options objectForKey:@"Password"];

  if (@available(iOS 11.0, *)) {
      if (ssidString && [ssidString length]) {
          NEHotspotConfiguration *configuration = [[NEHotspotConfiguration
          alloc] initWithSSID:ssidString 
					passphrase:passwordString 
						isWEP:(BOOL)false];

          configuration.joinOnce = false;

          [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration completionHandler:^(NSError * _Nullable error) {
              
              [self fetchSSIDInfoWithCompletion:^(NSDictionary *ssidInfo) {
                  NSString *ssid = [ssidInfo objectForKey:(id)kCNNetworkInfoKeySSID];
                  if ([ssid isEqualToString:ssidString]) {
                      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
                  } else {
                      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.description];
                  }
                  [self.commandDelegate sendPluginResult:pluginResult
                  callbackId:command.callbackId];
              }];
          }];

      } else {
          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
          [self.commandDelegate sendPluginResult:pluginResult
          callbackId:command.callbackId];
      }
  } else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
      [self.commandDelegate sendPluginResult:pluginResult
      callbackId:command.callbackId];
  }


}

- (void)iOSConnectOpenNetwork:(CDVInvokedUrlCommand*)command {

    __block CDVPluginResult *pluginResult = nil;

    NSString * ssidString;
    NSDictionary* options = [[NSDictionary alloc]init];

    options = [command argumentAtIndex:0];
    ssidString = [options objectForKey:@"Ssid"];

    if (@available(iOS 11.0, *)) {
        if (ssidString && [ssidString length]) {
            NEHotspotConfiguration *configuration = [[NEHotspotConfiguration
            alloc] initWithSSID:ssidString];

            configuration.joinOnce = false;

            [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration completionHandler:^(NSError * _Nullable error) {
                
                [self fetchSSIDInfoWithCompletion:^(NSDictionary *ssidInfo) {
                    NSString *ssid = [ssidInfo objectForKey:(id)kCNNetworkInfoKeySSID];
                    if ([ssid isEqualToString:ssidString]){
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
                    }else{
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.description];
                    }
                    [self.commandDelegate sendPluginResult:pluginResult
                    callbackId:command.callbackId];
                }];
            }];

        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
            [self.commandDelegate sendPluginResult:pluginResult
            callbackId:command.callbackId];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
        [self.commandDelegate sendPluginResult:pluginResult
        callbackId:command.callbackId];
    }


}

- (void)iOSDisconnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

  NSString * ssidString;
  NSDictionary* options = [[NSDictionary alloc]init];

  options = [command argumentAtIndex:0];
  ssidString = [options objectForKey:@"Ssid"];

  if (@available(iOS 11.0, *)) {
      if (ssidString && [ssidString length]) {
      [[NEHotspotConfigurationManager sharedManager] removeConfigurationForSSID:ssidString];
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
    } else {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
    }
  } else {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
  }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getConnectedSSID:(CDVInvokedUrlCommand*)command {
    __block NSString *ssid = nil;
    __block CDVPluginResult *pluginResult = nil;
    if (@available(iOS 14.0, *)) {
        [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
            ssid = [currentNetwork SSID];
            NSLog(@"debugjeje");

            NSLog(@"%@", currentNetwork);
            if (ssid && [ssid length]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssid];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
            }
            [self.commandDelegate sendPluginResult:pluginResult
                                        callbackId:command.callbackId];
        }];
    } else {
        NSArray *ifs = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
        NSDictionary *info;
        for (NSString *ifnam in ifs) {
            info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
            if (info && [info count]) {
                ssid = [info objectForKey:@"SSID"];
                break;
            }
        }
        if (ssid && [ssid length]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssid];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
        }
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }

}


- (void)getConnectedBSSID:(CDVInvokedUrlCommand*)command {
    __block CDVPluginResult *pluginResult = nil;

    [self fetchSSIDInfoWithCompletion:^(NSDictionary *info) {
        NSString *bssid = [info objectForKey:(id)kCNNetworkInfoKeyBSSID]; //@"BSSID"

        if (bssid && [bssid length]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:bssid];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
        }

        [self.commandDelegate sendPluginResult:pluginResult
        callbackId:command.callbackId];
    }];
}

- (void)isWifiEnabled:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    NSString *isWifiOn = [self isWiFiEnabled] ? @"1" : @"0";

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:isWifiOn];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)setWifiEnabled:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

// Android functions

- (void)addNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)removeNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)androidConnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)androidDisconnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)listNetworks:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getScanResults:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)startScan:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)disconnect:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)isConnectedToInternet:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canConnectToInternet:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canPingWifiRouter:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canConnectToRouter:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}


@end
