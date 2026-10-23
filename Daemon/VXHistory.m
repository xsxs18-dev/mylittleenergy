#import "VXHistory.h"
#import <fcntl.h>
#import <unistd.h>

#define VX_MAX_SESSIONS 300
#define VX_MAX_HEALTH 3650

@implementation VXHistory

+ (void)appendSample:(VXSample)sample {
	VXEnsureDirectory();
	BOOL existed = [NSFileManager.defaultManager fileExistsAtPath:VX_HISTORY_PATH];
	int fd = open(VX_HISTORY_PATH.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
	if (fd < 0) return;
	// A partial record from a crash would shift every later record, so the file is kept at a multiple of the record size.
	off_t size = lseek(fd, 0, SEEK_END);
	if (size % sizeof(VXSample)) (void)ftruncate(fd, size - size % sizeof(VXSample));
	(void)write(fd, &sample, sizeof(sample));
	close(fd);
	if (!existed && getuid() == 0) chown(VX_HISTORY_PATH.fileSystemRepresentation, 501, 501);
}

+ (uint32_t)lastSampleTime {
	int fd = open(VX_HISTORY_PATH.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) return 0;
	off_t size = lseek(fd, 0, SEEK_END);
	uint32_t time = 0;
	if (size >= (off_t)sizeof(VXSample)) {
		VXSample sample;
		off_t offset = size - size % sizeof(VXSample) - sizeof(VXSample);
		if (pread(fd, &sample, sizeof(sample), offset) == sizeof(sample)) time = sample.time;
	}
	close(fd);
	return time;
}

+ (void)pruneOlderThanDays:(NSInteger)days {
	NSData *data = [NSData dataWithContentsOfFile:VX_HISTORY_PATH];
	if (!data.length) return;
	uint32_t cutoff = (uint32_t)(NSDate.date.timeIntervalSince1970 - MAX(days, 1) * 86400);
	NSUInteger count = data.length / sizeof(VXSample);
	const VXSample *samples = data.bytes;
	NSUInteger first = 0;
	while (first < count && samples[first].time < cutoff) first++;
	if (first == 0) return;
	NSData *kept = [data subdataWithRange:NSMakeRange(first * sizeof(VXSample), (count - first) * sizeof(VXSample))];
	VXWriteFile(VX_HISTORY_PATH, kept);
}

+ (NSArray<NSArray<NSNumber *> *> *)levelsSince:(NSTimeInterval)since bucket:(NSTimeInterval)bucket {
	NSData *data = [NSData dataWithContentsOfFile:VX_HISTORY_PATH];
	NSUInteger count = data.length / sizeof(VXSample);
	const VXSample *samples = data.bytes;
	NSMutableArray *levels = [NSMutableArray array];
	uint32_t lastBucket = 0;
	// Newest records are at the end, so only the tail is walked.
	NSUInteger start = count;
	while (start > 0 && samples[start - 1].time >= since) start--;
	for (NSUInteger i = start; i < count; i++) {
		uint32_t key = (uint32_t)(samples[i].time / bucket);
		if (key == lastBucket) continue;
		lastBucket = key;
		[levels addObject:@[@(samples[i].time), @(samples[i].level)]];
	}
	return levels;
}

+ (NSArray<NSArray<NSNumber *> *> *)drainEntriesSince:(NSTimeInterval)since {
	NSData *data = [NSData dataWithContentsOfFile:VX_HISTORY_PATH];
	NSUInteger count = data.length / sizeof(VXSample);
	const VXSample *samples = data.bytes;
	NSUInteger start = count;
	while (start > 0 && samples[start - 1].time >= since) start--;
	NSMutableArray *entries = [NSMutableArray arrayWithCapacity:count - start];
	for (NSUInteger i = start; i < count; i++) {
		[entries addObject:@[@(samples[i].time), @(samples[i].level), @((samples[i].flags & VXSampleExternal) != 0)]];
	}
	return entries;
}

+ (void)appendSession:(NSDictionary *)session {
	NSMutableArray *sessions = [VXReadJSON(VX_SESSIONS_PATH) mutableCopy];
	if (![sessions isKindOfClass:[NSMutableArray class]]) sessions = [NSMutableArray array];
	[sessions addObject:session];
	if (sessions.count > VX_MAX_SESSIONS) [sessions removeObjectsInRange:NSMakeRange(0, sessions.count - VX_MAX_SESSIONS)];
	VXWriteJSON(VX_SESSIONS_PATH, sessions);
}

+ (void)recordHealth:(NSDictionary *)entry forDay:(NSString *)day {
	NSMutableArray *entries = [VXReadJSON(VX_HEALTH_PATH) mutableCopy];
	if (![entries isKindOfClass:[NSMutableArray class]]) entries = [NSMutableArray array];
	NSMutableDictionary *record = [entry mutableCopy];
	record[@"day"] = day;
	if ([[entries.lastObject valueForKey:@"day"] isEqual:day]) entries[entries.count - 1] = record;
	else [entries addObject:record];
	if (entries.count > VX_MAX_HEALTH) [entries removeObjectsInRange:NSMakeRange(0, entries.count - VX_MAX_HEALTH)];
	VXWriteJSON(VX_HEALTH_PATH, entries);
}

+ (void)clearAll {
	for (NSString *path in @[VX_HISTORY_PATH, VX_SESSIONS_PATH, VX_HEALTH_PATH]) {
		[NSFileManager.defaultManager removeItemAtPath:path error:nil];
	}
}

@end
