#import <Foundation/Foundation.h>
#import "VXEngine.h"

static void VXInstallSignal(int number) {
	signal(number, SIG_IGN);
	dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, number, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(source, ^{
		[VXEngine.shared shutdown];
		exit(0);
	});
	dispatch_resume(source);
	// Kept alive for the life of the process.
	(void)CFBridgingRetain(source);
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		VXInstallSignal(SIGTERM);
		VXInstallSignal(SIGINT);
		VXInstallSignal(SIGHUP);
		[VXEngine.shared start];
	}
	dispatch_main();
}
