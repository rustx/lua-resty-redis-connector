use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

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
		local rc = require("resty.redis.connector").new()

		local sentinel, err = rc:connect{ url = "redis://127.0.0.1:6381" }
		assert(sentinel and not err, "sentinel should connect without errors")

		local master, err = require("resty.redis.sentinel").get_master(
			sentinel,
			"mymaster"
		)

		assert(master and not err, "get_master should return the master")

		assert(master.host == "127.0.0.1" and tonumber(master.port) == 6379,
			"host should be 127.0.0.1 and port should be 6379")

		sentinel:close()
	}
}
--- request
GET /t
--- no_error_log
[error]


=== TEST 2: Get slaves
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local rc = require("resty.redis.connector").new()

        local sentinel, err = rc:connect{ url = "redis://127.0.0.1:6381" }
        assert(sentinel and not err, "sentinel should connect without error")

        local slaves, err = require("resty.redis.sentinel").get_slaves(
            sentinel,
            "mymaster"
        )

        assert(slaves and not err, "slaves should be returned without error")

		local slaveports = { ["6378"] = false, ["6380"] = false }

		for _,slave in ipairs(slaves) do
			slaveports[tostring(slave.port)] = true
		end

		assert(slaveports["6378"] == true and slaveports["6380"] == true,
			"slaves should both be found")

        sentinel:close()
    }
}
--- request
GET /t
--- no_error_log
[error]
--- ONLY


=== TEST 3: Get only healthy slaves
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local rc = require("resty.redis.connector").new()

        local sentinel, err = rc:connect({ url = "redis://127.0.0.1:6381" })
		assert(sentinel and not err, "sentinel should connect without error")

        local slaves, err = require("resty.redis.sentinel").get_slaves(
			sentinel,
			"mymaster"
		)

		assert(slaves and not err, "slaves should be returned without error")

		local slaveports = { ["6378"] = false, ["6380"] = false }

		for _,slave in ipairs(slaves) do
			slaveports[tostring(slave.port)] = true
		end

		assert(slaveports["6378"] == true and slaveports["6380"] == true,
			"slaves should both be found")

		-- connect to one and remove it
		local r = require("resty.redis.connector").new():connect({
			port = 6378,
		})
        r:slaveof("127.0.0.1", 7000)

        ngx.sleep(9)

        local slaves, err = require("resty.redis.sentinel").get_slaves(
			sentinel,
			"mymaster"
		)

		assert(slaves and not err, "slaves should be returned without error")

		local slaveports = { ["6378"] = false, ["6380"] = false }

		for _,slave in ipairs(slaves) do
			slaveports[tostring(slave.port)] = true
		end

		assert(slaveports["6378"] == false and slaveports["6380"] == true,
			"only 6380 should be found")

        r:slaveof("127.0.0.1", 6379)
        sentinel:close()
    }
}
--- request
    GET /t
--- timeout: 10
--- no_error_log
[error]
