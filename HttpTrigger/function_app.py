import azure.functions as func
import requests
import logging
import os
from azure.communication.email import EmailClient

API_KEY = os.getenv("API_KEY")
connection_string = os.getenv("AZURE_EMAIL_CONNECTION_STRING")
email_sender = os.getenv("AZURE_EMAIL_SENDER")
email_recipient = os.getenv("AZURE_EMAIL_RECIPIENT")


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
    headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    }

    if req.method == "OPTIONS":
        # Pre-flight request. Reply successfully:
        return func.HttpResponse("OK", status_code=200, headers=headers)
    else:
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
            # Send email if PM2_5 is above 20
            if pollution_components["pm2_5"] > 20:
                message = {
                    "content": {
                        "subject": f"Air Pollution Alert [{city_name}] 🚨",
                        "plainText": f"Air pollution alert! Air component PM2.5 is above 20 in {city_name}. Please take necessary precautions.",
                        "html": f"<html><h1>Air pollution alert! </h1><p>Air component PM2.5 is above 20 in your {city_name}. Please take necessary precautions.</p></html>",
                    },
                    "recipients": {
                        "to": [
                            {
                                "address": f"{email_recipient}",
                                "displayName": "User",
                            }
                        ]
                    },
                    "senderAddress": f"{email_sender}",
                }

                POLLER_WAIT_TIME = 10

            try:
                email_client = EmailClient.from_connection_string(connection_string)
                print(email_client)

                poller = email_client.begin_send(message)
                print(poller)

                time_elapsed = 0
                while not poller.done():
                    print("Email send poller status: " + poller.status())

                    poller.wait(POLLER_WAIT_TIME)
                    time_elapsed += POLLER_WAIT_TIME

                    if time_elapsed > 18 * POLLER_WAIT_TIME:
                        raise RuntimeError("Polling timed out.")

                if poller.result()["status"] == "Succeeded":
                    print(
                        f"Successfully sent the email (operation id: {poller.result()['id']})"
                    )
                else:
                    raise RuntimeError(str(poller.result()["error"]))

            except Exception as ex:
                print(ex)

            components_items = list(pollution_components.items())

            if city_data:
                os.environ["CITY_NAME"] = city_name
                response = func.HttpResponse(
                    f"Pollution components: {components_items}"
                )
                response.headers["Access-Control-Allow-Origin"] = "*"
                response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
                response.headers["Access-Control-Allow-Headers"] = "Content-Type"
                return response
            else:
                return func.HttpResponse("City not found!", status_code=404)
        else:
            return func.HttpResponse(
                "Please provide a city name in the query string or in the request body.",
                status_code=400,
            )


@app.timer_trigger(schedule="25,50 * * * * *", arg_name="timer")
def run_airlog_http_trigger(timer: func.TimerRequest) -> None:
    logging.info("Running airlog_http_trigger on a timer...")
    city_name = os.getenv("CITY_NAME", "Mrągowo")
    logging.info(f"Subscribing pollution alert for city: {city_name}")
    req_params = {"city_name": city_name}
    req = func.HttpRequest(
        method="GET",
        url="/api/airlog_http_trigger",
        params={"city_name": req_params["city_name"]},
        body=None,
    )
    airlog_http_trigger(req)
