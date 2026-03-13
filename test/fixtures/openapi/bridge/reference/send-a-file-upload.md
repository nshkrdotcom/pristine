# Send A File Upload

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture send a file upload
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
paths:
  /v1/file_uploads/{file_upload_id}/send:
    post:
      tags:
        - FileUploads
      summary: Upload a file part
      operationId: upload-file
      parameters:
        - in: path
          name: file_upload_id
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
          description: File upload received
````
