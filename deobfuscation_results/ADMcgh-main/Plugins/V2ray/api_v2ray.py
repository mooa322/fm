from flask import Flask, request, Response
import json

# Ruta del archivo de configuración de v2ray, cambiar v2 por x si es para xray
CONFIG_PATH = "/etc/v2ray/config.json"

app = Flask(__name__)

def cargar_clientes():
    """
    Carga y devuelve la lista de IDs desde el archivo de configuración de v2ray.
    """
    try:
        with open(CONFIG_PATH, "r") as f:
            data = json.load(f)
            clientes = []
            for inbound in data.get("inbounds", []):
                settings = inbound.get("settings", {})
                for client in settings.get("clients", []):
                    if "id" in client:
                        clientes.append(client["id"])
            return clientes
    except Exception as e:
        print(f"Error leyendo config.json: {e}")
        return []


@app.route("/", methods=["GET"])
def validar_uuid():
    """
    Verifica si el UUID enviado está en la lista de clientes.
    Ejemplo: http://miippublica:889/?uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    """
    uuid = request.args.get("uuid", "")

    if not uuid:
        return Response('FALTA EL PARAMETRO "UUID" EN LA URL, Power by @ChumoGH', mimetype="text/plain")

    clientes = cargar_clientes()

    if uuid in clientes:
        return Response("OK", mimetype="text/plain")
    else:
        return Response("SERVICIO DE AUTENTICACION V2RAY by @ChumoGH", mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=889)
