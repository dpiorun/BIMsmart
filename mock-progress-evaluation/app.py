from flask import Flask, request, jsonify


app = Flask(__name__)
app.config["DEBUG"] = True