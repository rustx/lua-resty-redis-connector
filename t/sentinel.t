use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
lua_package_path "$pwd/lib/?.lua;;";

init_by_lua_block {
    require("luacov.runner").init()
}
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();

run_tests();

__DATA__

=== TEST 1: Get the master
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local redis_connector = require "resty.redis.connector"
        local rc = redis_connector.new()

        local sentinel, err = rc:connect{ url = "redis://127.0.0.1:6381" }
        if not sentinel then
            ngx.say("failed to connect: ", err)
            return
        end

        local redis_sentinel = require "resty.redis.sentinel"

        local master, err = redis_sentinel.get_master(sentinel, "mymaster")
        if not master then
            ngx.say(err)
        else
            ngx.say("host: ", master.host)
            ngx.say("port: ", master.port)
        end

        sentinel:close()
        }
}
--- request
    GET /t
--- response_body
host: 127.0.0.1
port: 6379
--- no_error_log
[error]


=== TEST 2: Get slaves
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local redis_connector = require "resty.redis.connector"
        local rc = redis_connector.new()

        local sentinel, err = rc:connect{ url = "redis://127.0.0.1:6381" }
        if not sentinel then
            ngx.say("failed to connect: ", err)
            return
        end

        local redis_sentinel = require "resty.redis.sentinel"

        local slaves, err = redis_sentinel.get_slaves(sentinel, "mymaster")
        if not slaves then
            ngx.say(err)
        else
            -- order is undefined
            local all = {}
            for i,slave in ipairs(slaves) do
                all[i] = tonumber(slave.port)
            end
            table.sort(all)
            for _,p in ipairs(all) do
                ngx.say(p)
            end
        end

        sentinel:close()
    }
}
--- request
    GET /t
--- response_body
6378
6380
--- no_error_log
[error]

=== TEST 3: Get only healthy slaves
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local redis = require "resty.redis"
        local r = redis.new()
        r:connect("127.0.0.1", 6378)
        r:slaveof("127.0.0.1", 7000)

        ngx.sleep(9)

        local redis_connector = require "resty.redis.connector"
        local rc = redis_connector.new()

        local sentinel, err = rc:connect{ url = "redis://127.0.0.1:6381" }
        if not sentinel then
            ngx.say("failed to connect: ", err)
            return
        end

        local redis_sentinel = require "resty.redis.sentinel"

        local slaves, err = redis_sentinel.get_slaves(sentinel, "mymaster")
        if not slaves then
            ngx.say(err)
        else
            for _,slave in ipairs(slaves) do
                ngx.say("host: ", slave.host)
                ngx.say("port: ", slave.port)
            end
        end

        sentinel:close()
    }
}
--- request
    GET /t
--- timeout: 10
--- response_body
host: 127.0.0.1
port: 6380
--- no_error_log
[error]
