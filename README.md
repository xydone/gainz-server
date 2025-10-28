# Gainz

Gainz is an unopinionated diet and exercise management platform.

# Features

- Calorie and macronutrient tracking.
- Exercise logging.
- Personalized goals for calories, nutrients, weight and exercise performance.

# Building

## Prerequisites

Gainz uses PostgreSQL and Redis under the hood. It is recommended that you use the Docker Compose file to automatically set it up.

Copy the `.env_example` file and rename it to `.env`. After filling in the information inside it, run:

```
docker compose --profile prod up -d
```

## Compiling

> [!IMPORTANT]
> Gainz is written on Zig 0.15.

Inside your terminal, run

```
zig build -Doptimize=ReleaseSafe
```

[There are more build modes if you wish to use them.](https://ziglang.org/documentation/0.14.1/#Build-Mode)

After compilation is done, the compiled executable will be inside the `zig-out\bin\` folder.

# Usage

Make sure the PostgreSQL and Redis instances are running. If they are not, run

```
docker compose --profile prod start
```

If you used the Docker Compose approach, your `.env` file should already be ready to use. If you opted for a different way to manage the instances, copy `.env-example`, rename it to `.env` and fill in the necessary information.

If you want to stop the server, stop the executable. You can turn off the Docker container by doing

```
docker compose --profile prod stop
```

# Testing

To get started testing, you need a test instance of the database. The easiest way of doing this is via the Docker Compose file.

Copy `.testing.env_example`, rename it to `.testing.env` and fill in the information.

After that, run

```
docker compose --profile test up -d
zig build test
```
