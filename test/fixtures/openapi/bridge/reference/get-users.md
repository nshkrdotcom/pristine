# Get Users

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture get users
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
paths:
  /v1/users:
    get:
      tags:
        - Users
      summary: List users
      operationId: get-users
      parameters:
        - in: query
          name: start_cursor
          required: false
          schema:
            type: string
        - in: query
          name: page_size
          required: false
          schema:
            type: integer
      responses:
        '200':
          description: User list
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  properties:
                    id:
                      type: string
````
