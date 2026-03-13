# Get Account Profile

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture get account profile
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
  schemas:
    accountProfileResponse:
      title: accountProfileResponse
      type: object
      required:
        - id
        - kind
      properties:
        id:
          type: string
          format: uuid
        kind:
          type: string
paths:
  /v1/accounts/me:
    get:
      tags:
        - Accounts
      summary: Retrieve the current account profile
      operationId: get-account-profile
      responses:
        '200':
          description: Current account profile
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/accountProfileResponse'
````
