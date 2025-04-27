import { Entity } from './BaseEntity.js';

export class TradeMessage extends Entity {
  static get table() {
    return 'trade_messages';
  }

  static get fields() {
    return Object.freeze({
      id: 'id',
      tradeId: 'trade_id',
      userId: 'user_id',
      body: 'body',
      updatedAt: 'updated_at',
      createdAt: 'created_at'
    });
  }

  static get schema() {
    return Object.freeze({
      type: 'object',
      required: ['id', 'tradeId', 'body'],
      properties: {
        id: {
          type: 'string',
          format: 'uuid',
          title: 'Message ID',
          description: 'The unique identifier of the trade message.'
        },
        tradeId: {
          type: 'string',
          format: 'uuid',
          title: 'Trade',
          description: 'The ID of the trade this message belongs to.'
        },
        userId: {
          type: 'string',
          format: 'uuid',
          nullable: true,
          title: 'Creator',
          description: 'The ID of the user who sent the message (nullable if user is deleted).'
        },
        body: {
          type: 'string',
          minLength: 1,
          maxLength: 5000,
          title: 'Message',
          description: 'Enter the message text here.'
        },
        updatedAt: {
          type: 'string',
          format: 'date-time',
          nullable: true,
          title: 'Updated At',
          description: 'Timestamp when the message was last edited.'
        },
        createdAt: {
          type: 'string',
          format: 'date-time',
          title: 'Created At',
          description: 'Timestamp when the message was created.'
        }
      }
    });
  }
}
