# Create A File Upload

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture create a file upload
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
paths:
  /v1/file_uploads:
    post:
      tags:
        - FileUploads
      summary: Create a file upload
      operationId: create-file
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
          description: File upload created
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: string
````
