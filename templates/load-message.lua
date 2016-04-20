-- Some constants to control the behavior. Eventually, we might want to control
-- those via Redis keys.
local bufferBucketInterval = 60 -- How long (in seconds) should a buffer bucket be?
local bufferBucketCount = 20    -- How many buffer buckets to retain (memory permitting)

-- First, parse the incoming JSON message.
local message = cjson.decode(ARGV[1])

-- Prepare a Message ID, add it to the message, and serialize.
message.redisMessageId = redis.call("INCR", "last-redisMessageId")
local messageJson = cjson.encode(message)

-- It's OK to index messages by app name, since app names are unique within an
-- environment.
local appName = message.app

-- First, deliver the message to listeners.
local publishRet = redis.call("PUBLISH", "stream-" .. appName, messageJson)

-- Now, we need to add the key to a buffer. We actually want to use multiple buffers
-- for each log stream, so that the Redis volatile-ttl policy will automatically
-- expire old logs for us, without entirely trimming the buffers. To that end, we
-- buffer logs into a new bucket every minute, which means we'll have 10 active
-- buckets per log stream, since our TTL on log buffers is 10 minutes.
local bufferBucketIndex = math.floor(message.unix_timestamp / bufferBucketInterval)
local bufferBucketName = "buffer-bucket-" .. appName .. "-" .. bufferBucketIndex

-- Add the message to the bucket, and set (or refresh) a TTL on the bucket.
-- This will ensure the message is eventually expired, and will also be used
-- by Redis to inform OOM eviction decisions.
redis.call("LPUSH", bufferBucketName, messageJson)
redis.call("EXPIRE", bufferBucketName, bufferBucketInterval * bufferBucketCount)

-- Finally, store the buffer name in our buffer map. The buffer map is a sorted
-- set where we sort buffer bucket names by their index, which means we can
-- query recent logs by hitting the more recent records in the set.
local bufferMapName = "buffer-map-" .. appName
redis.call("ZADD", bufferMapName, bufferBucketIndex, bufferBucketName)

-- Only retain the address of the buffers that may not have expired yet.
redis.call("ZREMRANGEBYRANK", bufferMapName, 0, -bufferBucketCount)

-- Set an TTL on the buffer map to make sure it too eventually gets evited.
redis.call("EXPIRE", bufferMapName, bufferBucketInterval * bufferBucketCount * 10)

-- Finally, return the number of subscribers for consistency with PUBLISH
return publishRet
