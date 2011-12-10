//
//  MixtapeAppDelegate.m
//  Mixtape
//
//  Created by orta therox on 29/09/2011.
//  Copyright 2011 http://ortatherox.com. All rights reserved.
//

#import "MixtapeAppDelegate.h"
#import "MainViewController.h"
#import "Settings.h"
#import "SetupViewController.h"
#import "Reachability.h"
#import "SPPlaylistFolderInternal.h"

@interface MixtapeAppDelegate (private)
- (void)showLoginController;
- (void)removeSetup;

- (void)waitForPlaylistsToLoad;
- (void)monitorForErrors;
- (BOOL)isOnline;
- (void)checkForOfflinePlaylists;
@end

@implementation MixtapeAppDelegate

@synthesize window = _window;
@synthesize mainViewController = _mainViewController;
@synthesize setupViewController = _setupViewController;
@synthesize playlists = _playlists;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        self.mainViewController = [[MainViewController alloc] initWithNibName:@"MainViewController_iPhone" bundle:nil]; 
    } else {
        self.mainViewController = [[MainViewController alloc] initWithNibName:@"MainViewController_iPad" bundle:nil]; 
    }
    self.window.rootViewController = self.mainViewController;
    [self.window makeKeyAndVisible];
    [self startSpotify];
    return YES;
}

-(void) startSpotify {
    srandom((unsigned int)time(NULL));
    
    [SPSession initializeSharedSessionWithApplicationKey:[NSData dataWithBytes:&g_appkey length:g_appkey_size]
                                               userAgent:ORUserAgent
                                                   error:nil];
    
    SPSession * session = [SPSession sharedSession];
    session.delegate = self; 
    
    if (![session storedCredentialsUserName]) {
        [self showLoginController];
    }else{ 
        NSLog(@"logged in as %@", [session storedCredentialsUserName]);
        [session attemptLoginWithStoredCredentials:nil];
    }
}

#pragma mark Spotify Session delegate methods

- (void)session:(SPSession *)aSession didFailToLoginWithError:(NSError *)error {
    NSLog(@"login error %@", [error localizedDescription]);
    NSDictionary * errorDictionary = [NSDictionary dictionaryWithObject:error forKey:ORNotificationErrorKey];
    [[NSNotificationCenter defaultCenter] postNotificationName: ORLoginFailed
                                                        object: nil 
                                                      userInfo: errorDictionary];
}

- (void)session:(SPSession *)aSession didEncounterNetworkError:(NSError *)error {
    NSLog(@"spotify is down");
    NSDictionary * errorDictionary = [NSDictionary dictionaryWithObject:error forKey:ORNotificationErrorKey];
    [[NSNotificationCenter defaultCenter] postNotificationName: ORLoginFailed
                                                        object: nil 
                                                      userInfo: errorDictionary];
}

- (void)session:(SPSession *)aSession didLogMessage:(NSString *)aMessage {
    NSLog(@"--- %@ ", aMessage);
}

- (void)sessionDidLoginSuccessfully:(SPSession *)aSession; {
    [self monitorForErrors];
    NSLog(@"logged in");
    if ([[NSUserDefaults standardUserDefaults] objectForKey:ORFolderID]) {
        [self removeSetup];
        if ([self isOnline]) {
            [self waitAndFillTrackPool];
        }else{
            [self checkForOfflinePlaylists];
        }
    }else{
        [[NSNotificationCenter defaultCenter] postNotificationName: ORLoggedIn object: nil];

    }
}

- (void)removeSetup {
    if (self.setupViewController) {
        [self.setupViewController.view removeFromSuperview];
    }
}

- (void)waitAndFillTrackPool {
	if ([[[SPSession sharedSession] userPlaylists] isLoaded] == NO) {
        [self performSelector:_cmd withObject:nil afterDelay:0.5];
        return;
    }
    
	// It can take a while for playlists to load, especially on a large account
    BOOL found = FALSE;
    NSNumber * folderIDNumber = [[NSUserDefaults standardUserDefaults] objectForKey:ORFolderID];
    uint64_t folderID = [folderIDNumber unsignedLongLongValue];
    NSArray * playlists =  [[SPSession sharedSession] userPlaylists].playlists;
    
    for (id playlistOrFolder in playlists) {
        if ([playlistOrFolder isKindOfClass:[SPPlaylistFolder class]]) {
            SPPlaylistFolder * folder = playlistOrFolder;
            if (folder.folderId == folderID) {
                self.playlists = folder.playlists;
                [self waitForPlaylistsToLoad];
                found = YES;
            }
        } 
    }
    if (!found) {
        [self performSelector:_cmd withObject:nil afterDelay:1.0];
        return;
    }
}

- (void)waitForPlaylistsToLoad {
    for (id item in self.playlists) {
        if ([item isKindOfClass:[SPPlaylist class]]) {
            SPPlaylist *playlist = item;
            if ([playlist isLoaded] == NO) {
                [self performSelector:_cmd withObject:nil afterDelay:0.5];
                return;
            }
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PlaylistsSet" object:self];
}

- (void)checkForOfflinePlaylists {
    NSNumber * folderIDNumber = [[NSUserDefaults standardUserDefaults] objectForKey:ORFolderID];
    uint64_t folderID = [folderIDNumber unsignedLongLongValue];

    SPPlaylistFolder * folder = [[SPPlaylistFolder alloc] initWithPlaylistFolderId:folderID container:[[SPSession sharedSession] userPlaylists] inSession:[SPSession sharedSession]];
    
    bool synced = YES;
    if (folder) {
        for (SPPlaylist * playlist in folder.playlists) {
            playlist.markedForOfflinePlayback = YES;
            for (SPTrack *track in playlist.items) {
                if (track.offlineStatus != SP_TRACK_OFFLINE_DONE) {
                    NSLog(@"ERROR - NOT SYNCED %@", track.name);
                    synced = NO;
                }
            }
            if ([playlist offlineStatus] != SP_PLAYLIST_OFFLINE_STATUS_YES) {
                NSLog(@"ERROR - NOT SYNCED");
                synced = NO;
            }
        }
    }
    if (synced) {
        self.playlists = folder.playlists;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PlaylistsSet" object:self];
    }
}

- (void)monitorForErrors {
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(showLoginController) 
                                                 name:ORLoginFailed 
                                               object:nil];
}

- (void)showLoginController {
    self.setupViewController = [[SetupViewController alloc] initWithNibName:@"SetupViewController" bundle:nil];
    

    [self.window.rootViewController.view addSubview:self.setupViewController.view];

    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(sessionDidLoginSuccessfully:) 
                                                 name:ORSongSent 
                                               object:nil];

}

- (BOOL)isOnline {
    return ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable);
}

- (void)applicationWillResignActive:(UIApplication *)application{}

- (void)applicationDidEnterBackground:(UIApplication *)application{}

- (void)applicationWillEnterForeground:(UIApplication *)application{}

- (void)applicationDidBecomeActive:(UIApplication *)application{    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ORAppResetKey]) {
        SPSession * session = [SPSession sharedSession];
        for (SPPlaylist *playlist in self.playlists) {
            [playlist setMarkedForOfflinePlayback:NO];
        }
        [session logout];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:ORFolderID];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:ORAppResetKey];
        [self startSpotify];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application{}

@end
