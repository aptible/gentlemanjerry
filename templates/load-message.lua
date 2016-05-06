-- Some parameters to control the behavior. Can be set via Redis keys.
-- How long (in seconds) should a given buffer bucket be?
local pBufferBucketInterval = tonumber(redis.call("GET", "conf-bufferBucketInterval")) or 60
-- How many buffer buckets should we retain?
local pBufferBucketCount = tonumber(redis.call("GET", "conf-bufferBucketCount")) or 20

-- Derived parameters
local pBufferLifetime = pBufferBucketInterval * pBufferBucketCount

-- First, parse and restructure the incoming message. We're pretty much
-- guaranteed this will be valid JSON, otherwise Gentlemanjerry (Logstash)
-- wouldn't send it to us (so, if it's not valid JSON, then something else must
-- have sent the message, and it's A-OK to bail with an exception).
local message = cjson.decode(ARGV[1])
message.redisMessageId = tonumber(redis.call("INCR", "last-redisMessageId"))
local messageJson = cjson.encode(message)

-- We're going to need to know the app name to route messages, and the
-- timestamp for the message. Unfortunately we're not guaranteed that those
-- fields will be here. In particular, app may be missing if JoeCool didn't
-- send it or if Gentlemanjerry failed to parse it. When that happens, we'll
-- just route this message to a junk bucket. This is unlikely to be useful for
-- users, but may let us troubleshoot errors more easily.
local messageAppName = message.app or "JUNK"
local messageTimestamp = message.unix_timestamp or 0

-- We'll index messages by app name, which is fine because app names are unique
-- within an environment and Log Drains are scoped to an environment, and
-- because users query logs on a per-app basis.

-- Make sure we deliver the message to subscribers waiting for it.
local publishRet = redis.call("PUBLISH", "stream-" .. messageAppName, messageJson)

-- Now, we need to add the key to a buffer. We actually want to use multiple buffers
-- for each log stream, so that the Redis volatile-ttl policy will automatically
-- expire old logs for us, without entirely trimming the buffers. To that end, we
-- buffer logs into a new bucket every minute, which means we'll have 10 active
-- buckets per log stream, since our TTL on log buffers is 10 minutes.
local bufferBucketIndex = math.floor(messageTimestamp / pBufferBucketInterval) * pBufferBucketInterval
local bufferBucketName = "buffer-bucket-" .. messageAppName .. "-" .. bufferBucketIndex

-- New messages are added at the right end of the bucket, which means that
-- messages will be sorted from first received to last received (note: the
-- ordering within a bucket is based on the order in which the messages were
-- received, not their actual timestamp).
redis.call("RPUSH", bufferBucketName, messageJson)

-- Set a  TTL, which ensures we eventually expire the bucket, and will be used
-- by Redis to inform OOM eviction decisions (oldest buckets - which will
-- expire the soonest - are evicted first).
redis.call("EXPIREAT", bufferBucketName, messageTimestamp + pBufferLifetime)

-- Finally, store the bucket name in a buffer map. The buffer map is a sorted
-- set where we sort bucket names by their timestamp. Thus, when we query the
-- set via ZRANGE ... 0 -1, we'll get the buckets from oldest to newest.
local bufferMapName = "buffer-map-" .. messageAppName
redis.call("ZADD", bufferMapName, bufferBucketIndex, bufferBucketName)

-- Truncate the buffer map to only retain the address of the buffers that may
-- not have expired yet.
redis.call("ZREMRANGEBYRANK", bufferMapName, 0, -pBufferBucketCount - 1)

-- Set a TTL to eventually expire the buffer map as well, but make sure it's
-- after the TTL of the last member. To do so, we ensure the buffer map expires
-- over one lifetime after we touched one of its members for the last time.
redis.call("EXPIRE", bufferMapName, pBufferLifetime + pBufferBucketInterval)

-- Finally, return the number of subscribers for consistency with PUBLISH
return publishRet
