# Get Self

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture get self
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
  schemas:
    partialUserObjectResponse:
      title: partialUserObjectResponse
      type: object
      required:
        - id
        - object
      properties:
        id:
          type: string
          format: uuid
        object:
          type: string
paths:
  /v1/users/me:
    get:
      tags:
        - Users
      summary: Retrieve the current user
      operationId: get-self
      responses:
        '200':
          description: Current user
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/partialUserObjectResponse'
````
