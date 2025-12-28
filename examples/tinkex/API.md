# Tinkex

## Overview

API: **Tinkex**
Version: 1.0.0

## Table of Contents

- [Sampling](#sampling)
- [Models](#models)


## Models

### GET /models/{model_id}

Get details for a specific model

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model_id` | string | Yes | Path parameter |


#### Response

Type: [`Model`](#model)


### GET /models

List all available models

#### Response

Type: [`ModelList`](#modellist)


## Sampling

### POST /samples

Create a new sample from a model

#### Request Body

Type: [`SampleRequest`](#samplerequest)


#### Response

Type: [`SampleResult`](#sampleresult)


### POST /samples/async

Create a sample asynchronously, returns a future

#### Request Body

Type: [`SampleRequest`](#samplerequest)


#### Response

Type: [`AsyncSampleResponse`](#asyncsampleresponse)


### POST /samples

Create a streaming sample from a model

#### Request Body

Type: [`SampleRequest`](#samplerequest)


#### Response

Type: [`SampleStreamEvent`](#samplestreamevent)


### GET /samples/{sample_id}

Get a sample result by ID

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sample_id` | string | Yes | Path parameter |


#### Response

Type: [`SampleResult`](#sampleresult)


## Type Reference

### ApiError

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | Yes |  |
| `type` | string | Yes |  |

### AsyncSampleResponse

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Sample ID to poll |
| `poll_url` | string | Yes |  |
| `status` | string | Yes |  |

### ContentBlock

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | No | Tool use ID (for tool_use blocks) |
| `input` | object | No | Tool input (for tool_use blocks) |
| `name` | string | No | Tool name (for tool_use blocks) |
| `text` | string | No | Text content (for text blocks) |
| `type` | string | Yes |  |

### Model

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `capabilities` | array | No | List of model capabilities |
| `context_length` | integer | Yes | Maximum context length in tokens |
| `created_at` | string | No | When the model was created |
| `description` | string | No | Model description |
| `id` | string | Yes | Unique model identifier |
| `name` | string | Yes | Human-readable model name |

### ModelList

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `data` | array | Yes |  |
| `has_more` | boolean | Yes |  |
| `next_cursor` | string | No |  |

### SampleRequest

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `max_tokens` | integer | No | Maximum tokens to generate |
| `metadata` | object | No | Custom metadata to attach |
| `model` | string | Yes | Model ID to use |
| `prompt` | string | Yes | Input prompt |
| `stop_sequences` | array | No | Sequences that stop generation |
| `stream` | boolean | No | Whether to stream the response |
| `temperature` | number | No | Sampling temperature |
| `top_p` | number | No | Nucleus sampling parameter |

### SampleResult

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `content` | array | Yes | Generated content blocks |
| `created_at` | string | Yes |  |
| `id` | string | Yes | Unique sample ID |
| `model` | string | Yes | Model used |
| `stop_reason` | string | Yes | Why generation stopped |
| `usage` | object | Yes | Token usage information |

### SampleStreamEvent

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `content_block` | object | No | Content block data |
| `delta` | object | No | Delta update |
| `error` | object | No | Error details |
| `index` | integer | No | Content block index |
| `message` | object | No | Partial message (for message_start) |
| `type` | string | Yes |  |
| `usage` | object | No | Usage information |

### Usage

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `input_tokens` | integer | Yes |  |
| `output_tokens` | integer | Yes |  |
