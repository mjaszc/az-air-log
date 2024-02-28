from flask import Flask, render_template, request
import requests
from dotenv import load_dotenv
import os

app = Flask(__name__)

load_dotenv()

API_KEY = os.getenv("API_KEY")


def get_city_data(city, limit):
    api_url = f"http://api.openweathermap.org/geo/1.0/direct?q={city}&limit={limit}&appid={API_KEY}"
    response = requests.get(api_url)
    if response.status_code == 200:
        return response.json()
    else:
        return None


def get_air_pollution_data(lat, lon):
    api_url = f"http://api.openweathermap.org/data/2.5/air_pollution?lat={lat}&lon={lon}&appid={API_KEY}"
    response = requests.get(api_url)
    if response.status_code == 200:
        return response.json()
    else:
        return None


@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        name = request.form["city"]
        city_data = get_city_data(name, limit=1)
        city_name = city_data[0]["name"]
        lat = city_data[0]["lat"]
        lon = city_data[0]["lon"]

        pollution_data = get_air_pollution_data(lat, lon)
        pollution_components = pollution_data["list"][0]["components"]
        components_items = pollution_components.items()

        return render_template(
            "index.html",
            city_data=city_data,
            city_name=city_name,
            lat=lat,
            lon=lon,
            components=components_items,
        )
    else:
        return render_template("index.html")


if __name__ == "__main__":
    app.run(host="0.0.0.0")
