# List Projects

````yaml
openapi: 3.1.0
info:
  title: Bridge fixture list projects
  version: 1.0.0
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
paths:
  /v1/projects:
    get:
      tags:
        - Projects
      summary: List projects
      operationId: list-projects
      parameters:
        - in: query
          name: cursor
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
          description: Project list
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
