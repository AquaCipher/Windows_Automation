import requests
from requests_kerberos import HTTPKerberosAuth, OPTIONAL

# The API endpoint URL
url = "https://cyberark.example.com/AIMWebService/api/Accounts"

# The parameters for the request
params = {
    "AppID": "APP-ID",
    "Safe": "SAFE-NAME",
    "UserName": "account_name"
}

try:
    # Make the GET request using Kerberos authentication
    response = requests.get(url, params=params, auth=HTTPKerberosAuth(mutual_authentication=OPTIONAL))

    # Check if the request was successful
    response.raise_for_status()

    # Print the response data if successful
    print(response.json())

except requests.exceptions.RequestException as e:
    # Handle any exceptions that occur during the request
    print("Error:", e)
