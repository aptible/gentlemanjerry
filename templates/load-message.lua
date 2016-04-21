-- Some parameters to control the behavior. Can be set via Redis keys.
-- How long (in seconds) should a given buffer bucket be?
local pBufferBucketInterval = tonumber(redis.call("GET", "conf-bufferBucketInterval")) or 60
-- How many buffer buckets should we retain?
local pBufferBucketCount = tonumber(redis.call("GET", "conf-bufferBucketCount")) or 20

-- Derived parameters
local pBufferLifetime = pBufferBucketInterval * pBufferBucketCount

-- First, parse and restructure the incoming message.
local message = cjson.decode(ARGV[1])
message.redisMessageId = tonumber(redis.call("INCR", "last-redisMessageId"))
local messageJson = cjson.encode(message)

-- It's OK to index messages by app name, since app names are unique within an
-- environment.
local appName = message.app

-- Now, make sure we deliver the message to subscribers waiting for it.
local publishRet = redis.call("PUBLISH", "stream-" .. appName, messageJson)

-- Now, we need to add the key to a buffer. We actually want to use multiple buffers
-- for each log stream, so that the Redis volatile-ttl policy will automatically
-- expire old logs for us, without entirely trimming the buffers. To that end, we
-- buffer logs into a new bucket every minute, which means we'll have 10 active
-- buckets per log stream, since our TTL on log buffers is 10 minutes.
local bufferBucketIndex = math.floor(message.unix_timestamp / pBufferBucketInterval) * pBufferBucketInterval
local bufferBucketName = "buffer-bucket-" .. appName .. "-" .. bufferBucketIndex

-- Add the message to the bucket, and set (or refresh) a TTL on the bucket.
-- This will ensure the message is eventually expired, and will also be used
-- by Redis to inform OOM eviction decisions.
redis.call("LPUSH", bufferBucketName, messageJson)
redis.call("EXPIREAT", bufferBucketName, message.unix_timestamp + pBufferLifetime)

-- Finally, store the buffer name in a buffer map. The buffer map is a sorted
-- set where we sort buffer bucket names by their timestamp, which means we can
-- query recent logs by hitting the more recent records in the set.
local bufferMapName = "buffer-map-" .. appName
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
