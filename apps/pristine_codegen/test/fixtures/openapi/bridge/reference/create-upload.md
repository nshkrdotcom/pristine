# Create Upload

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture create upload
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
paths:
  /v1/uploads:
    post:
      tags:
        - Uploads
      summary: Create an upload
      operationId: create-upload
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                filename:
                  type: string
      responses:
        '200':
          description: Upload created
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: string
````
