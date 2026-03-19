# Send Upload Part

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture send upload part
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
paths:
  /v1/uploads/{upload_id}/parts:
    post:
      tags:
        - Uploads
      summary: Upload a file part
      operationId: upload-part
      parameters:
        - in: path
          name: upload_id
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required:
                - file
                - part_number
              properties:
                file:
                  type: string
                  format: binary
                part_number:
                  type: string
      responses:
        '200':
          description: Upload part received
````
