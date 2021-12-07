/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSDKBridgeAPITests.h"

@implementation FBSDKBridgeAPITests

- (void)setUp
{
  [super setUp];

  [FBSDKLoginManager resetTestEvidence];

  self.appURLSchemeProvider = [TestInternalUtility new];
  self.logger = [[TestLogger alloc] initWithLoggingBehavior:FBSDKLoggingBehaviorDeveloperErrors];
  self.urlOpener = [[TestInternalURLOpener alloc] initWithCanOpenUrl:YES];
  self.bridgeAPIResponseFactory = [TestBridgeAPIResponseFactory new];
  self.errorFactory = [TestErrorFactory new];

  [self configureSDK];

  self.api = [[FBSDKBridgeAPI alloc] initWithProcessInfo:[TestProcessInfo new]
                                                  logger:self.logger
                                               urlOpener:self.urlOpener
                                bridgeAPIResponseFactory:self.bridgeAPIResponseFactory
                                         frameworkLoader:self.frameworkLoader
                                    appURLSchemeProvider:self.appURLSchemeProvider
                                            errorFactory:self.errorFactory];
}

- (void)tearDown
{
  [FBSDKLoginManager resetTestEvidence];
  [TestLogger reset];

  [super tearDown];
}

- (void)configureSDK
{
  TestBackgroundEventLogger *backgroundEventLogger = [[TestBackgroundEventLogger alloc] initWithInfoDictionaryProvider:[TestBundle new]
                                                                                                           eventLogger:[TestAppEvents new]];
  TestServerConfigurationProvider *serverConfigurationProvider = [[TestServerConfigurationProvider alloc]
                                                                  initWithConfiguration:ServerConfigurationFixtures.defaultConfig];
  FBSDKApplicationDelegate *delegate = [[FBSDKApplicationDelegate alloc] initWithNotificationCenter:[TestNotificationCenter new]
                                                                                        tokenWallet:TestAccessTokenWallet.class
                                                                                           settings:[TestSettings new]
                                                                                     featureChecker:[TestFeatureManager new]
                                                                                          appEvents:[TestAppEvents new]
                                                                        serverConfigurationProvider:serverConfigurationProvider
                                                                                              store:[UserDefaultsSpy new]
                                                                          authenticationTokenWallet:TestAuthenticationTokenWallet.class
                                                                                    profileProvider:TestProfileProvider.class
                                                                              backgroundEventLogger:backgroundEventLogger
                                                                                    paymentObserver:[TestPaymentObserver new]];
  [delegate initializeSDKWithLaunchOptions:@{}];
}

// MARK: - Request completion block

- (void)testRequestCompletionBlockCalledWithSuccess
{
  TestBridgeAPIRequest *request = [TestBridgeAPIRequest requestWithURL:self.sampleUrl];
  FBSDKBridgeAPIResponseBlock responseBlock = ^void (FBSDKBridgeAPIResponse *response) {
    XCTFail("Should not call the response block when the request completion is called with success");
  };
  self.api.pendingRequest = request;
  self.api.pendingRequestCompletionBlock = ^(FBSDKBridgeAPIResponse *response) {};

  FBSDKSuccessBlock completion = [self.api _bridgeAPIRequestCompletionBlockWithRequest:request
                                                                            completion:responseBlock];
  // With Error
  completion(true, self.sampleError);
  [self assertPendingPropertiesNotCleared];

  // Without Error
  completion(true, nil);
  [self assertPendingPropertiesNotCleared];
}

- (void)testRequestCompletionBlockWithNonHttpRequestCalledWithoutSuccess
{
  TestBridgeAPIRequest *request = [TestBridgeAPIRequest requestWithURL:self.sampleUrl scheme:@"file"];

  FBSDKBridgeAPIResponseBlock responseBlock = ^void (FBSDKBridgeAPIResponse *response) {
    XCTAssertEqualObjects(
      response.request,
      request,
      @"The response should contain the original request"
    );
    TestSDKError *error = (TestSDKError *)response.error;
    XCTAssertEqual(
      error.type,
      ErrorTypeGeneral,
      @"The response should contain a general error"
    );
    XCTAssertEqual(
      error.code,
      FBSDKErrorAppVersionUnsupported,
      @"The error should use an app version unsupported error code"
    );
    XCTAssertEqualObjects(
      error.message,
      @"the app switch failed because the destination app is out of date",
      @"The error should use an appropriate error message"
    );
  };
  self.api.pendingRequest = request;
  self.api.pendingRequestCompletionBlock = ^(FBSDKBridgeAPIResponse *response) {};

  FBSDKSuccessBlock completion = [self.api _bridgeAPIRequestCompletionBlockWithRequest:request
                                                                            completion:responseBlock];
  // With Error
  completion(false, self.sampleError);
  [self assertPendingPropertiesCleared];

  // Without Error
  completion(false, nil);
  [self assertPendingPropertiesCleared];
}

- (void)testRequestCompletionBlockWithHttpRequestCalledWithoutSuccess
{
  TestBridgeAPIRequest *request = [TestBridgeAPIRequest requestWithURL:self.sampleUrl scheme:FBSDKURLSchemeHTTPS];
  FBSDKBridgeAPIResponseBlock responseBlock = ^void (FBSDKBridgeAPIResponse *response) {
    XCTAssertEqualObjects(
      response.request,
      request,
      @"The response should contain the original request"
    );
    TestSDKError *error = (TestSDKError *)response.error;
    XCTAssertEqual(
      error.type,
      ErrorTypeGeneral,
      @"The response should contain a general error"
    );
    XCTAssertEqual(
      error.code,
      FBSDKErrorBrowserUnavailable,
      @"The error should use a browser unavailable error code"
    );
    XCTAssertEqualObjects(
      error.message,
      @"the app switch failed because the browser is unavailable",
      @"The response should use an appropriate error message"
    );
  };
  self.api.pendingRequest = request;
  self.api.pendingRequestCompletionBlock = ^(FBSDKBridgeAPIResponse *response) {};

  FBSDKSuccessBlock completion = [self.api _bridgeAPIRequestCompletionBlockWithRequest:request
                                                                            completion:responseBlock];
  // With Error
  completion(false, self.sampleError);
  [self assertPendingPropertiesCleared];

  // Without Error
  completion(false, nil);
  [self assertPendingPropertiesCleared];
}

// MARK: - Safari View Controller Delegate Methods

- (void)testSafariVcDidFinishWithPendingUrlOpener
{
  FBSDKLoginManager *urlOpener = [FBSDKLoginManager new];
  self.api.pendingURLOpen = urlOpener;
  self.api.safariViewController = (SFSafariViewController *)ViewControllerSpy.makeDefaultSpy;

  // Setting a pending request so we can assert that it's nilled out upon cancellation
  self.api.pendingRequest = self.sampleTestBridgeAPIRequest;

  // Funny enough there's no check that the safari view controller from the delegate
  // is the same instance stored in the safariViewController property
  [self.api safariViewControllerDidFinish:self.api.safariViewController];

  XCTAssertNil(self.api.pendingURLOpen, "Should remove the reference to the pending url opener");
  XCTAssertNil(
    self.api.safariViewController,
    "Should remove the reference to the safari view controller when the delegate method is called"
  );

  XCTAssertNil(self.api.pendingRequest, "Should cancel the request");
  XCTAssertTrue(urlOpener.openUrlWasCalled, "Should ask the opener to open a url (even though there is not one provided");
  XCTAssertNil(FBSDKLoginManager.capturedOpenUrl, "The url opener should be called with nil arguments");
  XCTAssertNil(FBSDKLoginManager.capturedSourceApplication, "The url opener should be called with nil arguments");
  XCTAssertNil(FBSDKLoginManager.capturedAnnotation, "The url opener should be called with nil arguments");
}

- (void)testSafariVcDidFinishWithoutPendingUrlOpener
{
  self.api.safariViewController = (id)ViewControllerSpy.makeDefaultSpy;

  // Setting a pending request so we can assert that it's nilled out upon cancellation
  self.api.pendingRequest = self.sampleTestBridgeAPIRequest;

  // Funny enough there's no check that the safari view controller from the delegate
  // is the same instance stored in the safariViewController property
  [self.api safariViewControllerDidFinish:self.api.safariViewController];

  XCTAssertNil(self.api.pendingURLOpen, "Should remove the reference to the pending url opener");
  XCTAssertNil(
    self.api.safariViewController,
    "Should remove the reference to the safari view controller when the delegate method is called"
  );

  XCTAssertNil(self.api.pendingRequest, "Should cancel the request");
  XCTAssertNil(FBSDKLoginManager.capturedOpenUrl, "The url opener should not be called");
  XCTAssertNil(FBSDKLoginManager.capturedSourceApplication, "The url opener should not be called");
  XCTAssertNil(FBSDKLoginManager.capturedAnnotation, "The url opener should not be called");
}

// MARK: - ContainerViewController Delegate Methods

- (void)testViewControllerDidDisappearWithSafariViewController
{
  UIViewController *viewControllerSpy = ViewControllerSpy.makeDefaultSpy;
  self.api.safariViewController = (SFSafariViewController *)viewControllerSpy;
  FBSDKContainerViewController *container = [FBSDKContainerViewController new];

  // Setting a pending request so we can assert that it's nilled out upon cancellation
  self.api.pendingRequest = self.sampleTestBridgeAPIRequest;

  [self.api viewControllerDidDisappear:container animated:NO];

  XCTAssertEqualObjects(_logger.capturedContents, @"**ERROR**:\n The SFSafariViewController's parent view controller was dismissed.\nThis can happen if you are triggering login from a UIAlertController. Instead, make sure your top most view controller will not be prematurely dismissed.");
  XCTAssertNil(self.api.pendingRequest, "Should cancel the request");
}

- (void)testViewControllerDidDisappearWithoutSafariViewController
{
  FBSDKContainerViewController *container = [FBSDKContainerViewController new];

  // Setting a pending request so we can assert that it's nilled out upon cancellation
  self.api.pendingRequest = self.sampleTestBridgeAPIRequest;

  [self.api viewControllerDidDisappear:container animated:NO];

  XCTAssertNotNil(self.api.pendingRequest, "Should not cancel the request");
  XCTAssertNil(_logger.capturedContents, @"Expected nothing to be logged");
}

// MARK: - Bridge Response Url Handling

- (void)testHandlingBridgeResponseWithInvalidScheme
{
  [self stubBridgeApiResponseWithUrlCreation];
  self.appURLSchemeProvider.stubbedScheme = @"foo";

  BOOL result = [self.api _handleBridgeAPIResponseURL:self.sampleUrl sourceApplication:@""];

  XCTAssertFalse(result, "Should not successfully handle bridge api response url with an invalid url scheme");
  [self assertPendingPropertiesCleared];
}

- (void)testHandlingBridgeResponseWithInvalidHost
{
  [self stubBridgeApiResponseWithUrlCreation];
  self.appURLSchemeProvider.stubbedScheme = self.sampleUrl.scheme;

  BOOL result = [self.api _handleBridgeAPIResponseURL:self.sampleUrl sourceApplication:@""];

  XCTAssertFalse(result, "Should not successfully handle bridge api response url with an invalid url host");
  [self assertPendingPropertiesCleared];
}

- (void)testHandlingBridgeResponseWithMissingRequest
{
  [self stubBridgeApiResponseWithUrlCreation];
  self.appURLSchemeProvider.stubbedScheme = self.validBridgeResponseUrl.scheme;

  BOOL result = [self.api _handleBridgeAPIResponseURL:self.validBridgeResponseUrl sourceApplication:@""];

  XCTAssertFalse(result, "Should not successfully handle bridge api response url with a missing request");
  [self assertPendingPropertiesCleared];
}

- (void)testHandlingBridgeResponseWithMissingCompletionBlock
{
  [self stubBridgeApiResponseWithUrlCreation];
  self.appURLSchemeProvider.stubbedScheme = self.validBridgeResponseUrl.scheme;
  self.api.pendingRequest = [TestBridgeAPIRequest requestWithURL:self.sampleUrl];

  BOOL result = [self.api _handleBridgeAPIResponseURL:self.validBridgeResponseUrl sourceApplication:@""];

  XCTAssertTrue(result, "Should successfully handle bridge api response url with a missing completion block");
  [self assertPendingPropertiesCleared];
}

- (void)testHandlingBridgeResponseWithBridgeResponse
{
  FBSDKBridgeAPIResponse *response = [[FBSDKBridgeAPIResponse alloc] initWithRequest:[TestBridgeAPIRequest requestWithURL:self.sampleUrl]
                                                                  responseParameters:@{}
                                                                           cancelled:NO
                                                                               error:nil];
  self.bridgeAPIResponseFactory.stubbedResponse = response;
  self.appURLSchemeProvider.stubbedScheme = self.validBridgeResponseUrl.scheme;
  self.api.pendingRequest = [TestBridgeAPIRequest requestWithURL:self.sampleUrl];
  self.api.pendingRequestCompletionBlock = ^(FBSDKBridgeAPIResponse *_response) {
    XCTAssertEqualObjects(_response, response, "Should invoke the completion with the expected bridge api response");
  };

  BOOL result = [self.api _handleBridgeAPIResponseURL:self.validBridgeResponseUrl sourceApplication:@""];

  XCTAssertTrue(result, "Should successfully handle creation of a bridge api response");
  [self assertPendingPropertiesCleared];
}

- (void)testHandlingBridgeResponseWithBridgeError
{
  FBSDKBridgeAPIResponse *response = [[FBSDKBridgeAPIResponse alloc] initWithRequest:[TestBridgeAPIRequest requestWithURL:self.sampleUrl]
                                                                  responseParameters:@{}
                                                                           cancelled:NO
                                                                               error:self.sampleError];
  self.bridgeAPIResponseFactory.stubbedResponse = response;
  self.appURLSchemeProvider.stubbedScheme = self.validBridgeResponseUrl.scheme;
  self.api.pendingRequest = [TestBridgeAPIRequest requestWithURL:self.sampleUrl];
  self.api.pendingRequestCompletionBlock = ^(FBSDKBridgeAPIResponse *_response) {
    XCTAssertEqualObjects(_response, response, "Should invoke the completion with the expected bridge api response");
  };

  BOOL result = [self.api _handleBridgeAPIResponseURL:self.validBridgeResponseUrl sourceApplication:@""];

  XCTAssertTrue(result, "Should retry creation of a bridge api response if the first attempt has an error");
  [self assertPendingPropertiesCleared];
}

- (void)testHandlingBridgeResponseWithMissingResponseMissingError
{
  FBSDKBridgeAPIResponse *response = [[FBSDKBridgeAPIResponse alloc] initWithRequest:[TestBridgeAPIRequest requestWithURL:self.sampleUrl]
                                                                  responseParameters:@{}
                                                                           cancelled:NO
                                                                               error:nil];
  self.bridgeAPIResponseFactory.stubbedResponse = response;
  self.bridgeAPIResponseFactory.shouldFailCreation = YES;
  self.appURLSchemeProvider.stubbedScheme = self.validBridgeResponseUrl.scheme;
  self.api.pendingRequest = [TestBridgeAPIRequest requestWithURL:self.sampleUrl];
  self.api.pendingRequestCompletionBlock = ^(FBSDKBridgeAPIResponse *_response) {
    XCTFail("Should not invoke pending completion handler");
  };
  BOOL result = [self.api _handleBridgeAPIResponseURL:self.validBridgeResponseUrl sourceApplication:@""];

  XCTAssertFalse(result, "Should return false when a bridge response cannot be created");
  [self assertPendingPropertiesCleared];
}

// MARK: - Helpers

- (void)assertPendingPropertiesCleared
{
  XCTAssertNil(
    self.api.pendingRequest,
    "Should clear the pending request"
  );
  XCTAssertNil(
    self.api.pendingRequestCompletionBlock,
    "Should clear the pending request completion block"
  );
}

- (void)assertPendingPropertiesNotCleared
{
  XCTAssertNotNil(
    self.api.pendingRequest,
    "Should not clear the pending request"
  );
  XCTAssertNotNil(
    self.api.pendingRequestCompletionBlock,
    "Should not clear the pending request completion block"
  );
}

- (void)stubBridgeApiResponseWithUrlCreation
{
  FBSDKBridgeAPIResponse *response = [[FBSDKBridgeAPIResponse alloc] initWithRequest:[TestBridgeAPIRequest requestWithURL:self.sampleUrl]
                                                                  responseParameters:@{}
                                                                           cancelled:NO
                                                                               error:nil];
  self.bridgeAPIResponseFactory.stubbedResponse = response;
}

- (TestBridgeAPIRequest *)sampleTestBridgeAPIRequest
{
  return [[TestBridgeAPIRequest alloc] initWithUrl:self.sampleUrl
                                      protocolType:FBSDKBridgeAPIProtocolTypeWeb
                                            scheme:@"1"];
}

- (NSURL *)sampleUrl
{
  return [NSURL URLWithString:@"http://example.com"];
}

- (NSError *)sampleError
{
  return [NSError errorWithDomain:self.name code:0 userInfo:nil];
}

static inline NSString *StringFromBool(BOOL value)
{
  return value ? @"YES" : @"NO";
}

- (NSURL *)validBridgeResponseUrl
{
  return [NSURL URLWithString:@"http://bridge"];
}

NSString *const sampleSource = @"com.example";
NSString *const sampleAnnotation = @"foo";
NSOperatingSystemVersion const iOS10Version = { .majorVersion = 10, .minorVersion = 0, .patchVersion = 0 };

@end
