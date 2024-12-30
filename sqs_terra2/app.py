from flask import Flask, request, jsonify
import uuid
import boto3
import os

app = Flask(__name__)

# AWS Configuration
sqs = boto3.client('sqs', region_name='ap-south-1')
queue_url = os.getenv('SQS_QUEUE_URLhttps://sqs.ap-south-1.amazonaws.com/886436931873/Menu_sqs')
dynamodb = boto3.resource('dynamodb', region_name='ap-south-1')
table_name = os.getenv('orders-table')

# DynamoDB Table
order_table = dynamodb.Table('table_name')

@app.route('/orders', methods=['POST'])
def create_order():
    try:
        data = request.get_json()
        item = data.get('item')
        quantity = data.get('quantity')

        if not item or not isinstance(quantity, int):
            return jsonify({"error": "Invalid input"}), 400

        # Generate Order ID
        order_id = str(uuid.uuid4())
        order = {"order_id": order_id, "item": item, "quantity": quantity}

        # Push to SQS
        sqs.send_message(QueueUrl=queue_url, MessageBody=str(order))

        return jsonify({"order_id": order_id}), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/process-orders', methods=['POST'])
def process_orders():
    try:
        messages = sqs.receive_message(
            QueueUrl=queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=5
        )

        if 'Messages' not in messages:
            return jsonify({"message": "No orders to process"}), 200

        for message in messages['Messages']:
            body = eval(message['Body'])  # Deserialize order data

            # Save to DynamoDB
            order_table.put_item(Item=body)

            # Delete message from SQS
            sqs.delete_message(
                QueueUrl=queue_url, ReceiptHandle=message['ReceiptHandle']
            )

        return jsonify({"message": "Orders processed successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
