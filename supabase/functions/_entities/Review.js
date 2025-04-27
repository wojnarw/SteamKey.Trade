import { Entity } from './BaseEntity.js';

export class Review extends Entity {
  static get table() {
    return 'reviews';
  }

  static get fields() {
    return Object.freeze({
      id: 'id',
      subjectId: 'subject_id',
      userId: 'user_id',
      body: 'body',
      speed: 'speed',
      communication: 'communication',
      helpfulness: 'helpfulness',
      fairness: 'fairness',
      updatedAt: 'updated_at',
      createdAt: 'created_at'
    });
  }

  static get enums() {
    return Object.freeze({
      metric: Object.freeze({
        speed: 'speed',
        communication: 'communication',
        helpfulness: 'helpfulness',
        fairness: 'fairness'
      })
    });
  }

  static get schema() {
    return Object.freeze({
      type: 'object',
      required: ['id', 'subjectId', 'userId', 'speed', 'communication', 'helpfulness', 'fairness'],
      properties: {
        id: {
          type: 'string',
          format: 'uuid',
          title: 'ID',
          description: 'The unique identifier of the review.'
        },
        subjectId: {
          type: 'string',
          format: 'uuid',
          title: 'Subject',
          description: 'The ID of the user being reviewed.'
        },
        userId: {
          type: 'string',
          format: 'uuid',
          title: 'Reviewer',
          description: 'The ID of the user who wrote the review.'
        },
        body: {
          type: 'string',
          nullable: true,
          title: 'Comment',
          description: 'Optional comment about the review.'
        },
        speed: {
          type: 'integer',
          minimum: 1,
          maximum: 5,
          title: 'Speed',
          description: 'Rating for speed (1 = Slow, 5 = Fast).'
        },
        communication: {
          type: 'integer',
          minimum: 1,
          maximum: 5,
          title: 'Communication',
          description: 'Rating for communication (1 = Poor, 5 = Professional).'
        },
        helpfulness: {
          type: 'integer',
          minimum: 1,
          maximum: 5,
          title: 'Helpfulness',
          description: 'Rating for helpfulness (1 = Unhelpful, 5 = Facilitative).'
        },
        fairness: {
          type: 'integer',
          minimum: 1,
          maximum: 5,
          title: 'Fairness',
          description: 'Rating for fairness (1 = Lowballer, 5 = Generous).'
        },
        updatedAt: {
          type: 'string',
          format: 'date-time',
          nullable: true,
          title: 'Updated At',
          description: 'The timestamp when the review was last updated.'
        },
        createdAt: {
          type: 'string',
          format: 'date-time',
          title: 'Created At',
          description: 'The timestamp when the review was created.'
        }
      }
    });
  }

  static get labels() {
    return Object.freeze({
      ...super.labels,
      min: {
        speed: 'Slow',
        communication: 'Poor',
        helpfulness: 'Unhelpful',
        fairness: 'Lowballer'
      },
      max: {
        speed: 'Fast',
        communication: 'Professional',
        helpfulness: 'Facilitative',
        fairness: 'Generous'
      }
    });
  }

  static get icons() {
    return Object.freeze({
      speed: 'mdi-speedometer',
      communication: 'mdi-chat',
      helpfulness: 'mdi-help-circle',
      fairness: 'mdi-scale-balance'
    });
  }
}
