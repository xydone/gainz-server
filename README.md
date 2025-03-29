# Gainz

Gainz is a food tracker, macro tracker, calorie counter and more.

# Usage

There are two ways to run Gainz

## Docker

To get started, make sure you have Docker Compose installed. After that, run

```
docker-compose --profile prod up -d
```

To stop and start the containers you can use `docker-compose --profile prod stop` and `docker-compose --profile prod start`

## Zig

To get started, download [Zig 0.14.0](https://ziglang.org/download/#release-0.14.0) and run

```
zig build run
```

after that, you are ready to go.
Alternatively you can run

```c
zig build
```

and then open the `.exe` from the `zig-out` folder.

You will also need to run a Redis and PostgreSQL instance on the ports you specified in `.env`. View `.env_example` for an example of how your `.env` file is supposed to look like.
The PostgreSQL instance is supposed to be initialized with the `init.sql` script inside `docker-scripts/postgres`

# Testing

To get started testing, you need a test instance of the database. Copy `.testing.env_example` and follow the instructions.

After that, run

```
docker-compose --profile test up -d
zig build test
```
