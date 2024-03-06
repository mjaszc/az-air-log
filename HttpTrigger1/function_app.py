import azure.functions as func
import requests
import logging
import os

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


app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(route="airlog_http_trigger")
def airlog_http_trigger(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")

    city_name = req.params.get("city_name")
    if not city_name:
        try:
            req_body = req.get_json()
        except ValueError:
            pass
        else:
            city_name = req_body.get("city_name")

    if city_name:
        city_data = get_city_data(city_name, limit=1)

        city_name = city_data[0]["name"]
        lat = city_data[0]["lat"]
        lon = city_data[0]["lon"]

        pollution_data = get_air_pollution_data(lat, lon)
        pollution_components = pollution_data["list"][0]["components"]
        components_items = list(pollution_components.items())

        if city_data:
            return func.HttpResponse(f"Pollution components: {components_items}")
        else:
            return func.HttpResponse("City not found!", status_code=404)
    else:
        return func.HttpResponse(
            "Please provide a city name in the query string or in the request body.",
            status_code=400,
        )
