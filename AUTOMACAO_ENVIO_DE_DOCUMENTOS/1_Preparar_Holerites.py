{
  "name": "RH PRIME",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "holerites",
        "responseMode": "lastNode",
        "options": {}
      },
      "id": "da914c12-d497-441c-890b-e25662881371",
      "name": "Receber do Python",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "position": [
        -1120,
        32
      ],
      "webhookId": "36081825-c41e-4a82-87da-3b7f7f5b0288"
    },
    {
      "parameters": {
        "resource": "Chatting",
        "operation": "Send Text",
        "session": "default",
        "chatId": "={{ $('IF Caption Not Empty').item.json.body.chatId || $('Receber do Python').item.json.body.chatId }}",
        "text": "={{ $json.body.caption }}",
        "requestOptions": {}
      },
      "type": "n8n-nodes-waha.WAHA",
      "typeVersion": 202411,
      "position": [
        -672,
        32
      ],
      "id": "34832f37-433f-4f70-84bd-6605420bd9f8",
      "name": "Enviar Link Holerite WAHA",
      "credentials": {
        "wahaApi": {
          "id": "peJjsLQh8i0DW9NC",
          "name": "WAHA account"
        }
      },
      "onError": "continueErrorOutput"
    },
    {
      "parameters": {
        "resource": "Chatting",
        "operation": "Send Text",
        "session": "default",
        "chatId": "={{ ($('IF Caption Not Empty').item.json.body.chatId || $('Receber do Python').item.json.body.chatId).replace(/^(\\d{2})(\\d{8})@c\\.us$/, '$19$2@c.us') }}",
        "text": "={{ $('Receber do Python').item.json.body.caption }}",
        "requestOptions": {}
      },
      "type": "n8n-nodes-waha.WAHA",
      "typeVersion": 202411,
      "position": [
        -416,
        32
      ],
      "id": "dd615cf2-e277-4b99-b682-a77f2d88604a",
      "name": "Fallback Link Holerite WAHA",
      "credentials": {
        "wahaApi": {
          "id": "peJjsLQh8i0DW9NC",
          "name": "WAHA account"
        }
      }
    },
    {
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{ $json.body.caption }}",
              "operation": "isNotEmpty"
            }
          ]
        }
      },
      "id": "40099392-187a-468e-91c6-1aefe03c9123",
      "name": "IF Caption Not Empty",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [
        -928,
        32
      ]
    }
  ],
  "pinData": {},
  "connections": {
    "Receber do Python": {
      "main": [
        [
          {
            "node": "IF Caption Not Empty",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Enviar Link Holerite WAHA": {
      "main": [
        [],
        [
          {
            "node": "Fallback Link Holerite WAHA",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "IF Caption Not Empty": {
      "main": [
        [
          {
            "node": "Enviar Link Holerite WAHA",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "active": true,
  "settings": {
    "executionOrder": "v1",
    "binaryMode": "separate",
    "availableInMCP": false
  },
  "versionId": "8d89489f-f450-4e85-a45c-6e5b20ad9760",
  "meta": {
    "templateCredsSetupCompleted": true,
    "instanceId": "0f9910c092161db823c6a440e42444951a7195e90e3af46690fc7808ab273304"
  },
  "nodeGroups": [],
  "id": "H5fgZMzU2fcdkPUC",
  "tags": []
}
