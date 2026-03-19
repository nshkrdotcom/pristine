# Create Session Token

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture create session token
  version: 1.0.0
components:
  securitySchemes:
    basicAuth:
      type: http
      scheme: basic
paths:
  /v1/session_tokens:
    post:
      tags:
        - SessionTokens
      summary: Create a session token
      operationId: create-session-token
      security:
        - basicAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - grant_type
                - refresh_token
              properties:
                grant_type:
                  type: string
                refresh_token:
                  type: string
      responses:
        '200':
          description: Session token response
          content:
            application/json:
              schema:
                type: object
                properties:
                  access_token:
                    type: string
````
