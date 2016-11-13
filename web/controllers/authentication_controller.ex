defmodule Pwc.AuthenticationController do
  use Pwc.Web, :controller
  alias Pwc.Connection
  alias Pwc.Firewall
  alias Pwc.MacSolver
  alias Pwc.User
  require Logger

  plug :assign_remote_details

  defp assign_remote_details(conn, _) do
    conn
    |> assign(:remote_ip4, conn.remote_ip)
    |> assign(:remote_ip6, conn.remote_ip |> MacSolver.mac_of_ip4 |> MacSolver.ip6_of_mac)
    |> assign(:remote_mac, conn.remote_ip |> MacSolver.mac_of_ip4)
    |> assign(:remote_allowed, conn.remote_ip |> MacSolver.mac_of_ip4 |> Firewall.is_mac_allowed)
  end

  def show(conn, _params) do
    conn
    |> render("login.html")
  end

  def login(conn, %{"login_form" => %{"username" => username, "password" => password}}) do
    user = User
    |> Repo.get_by(username: username)

    case user do
      nil -> conn
             |> put_flash(:error, "Ce compte n'existe pas")
             |> render("login.html")
      user -> case Comeonin.Bcrypt.checkpw(password, user.encrypted_password) do
                false ->
                  conn
                  |> put_flash(:error, "Mot de passe incorrect")
                  |> render("login.html")
                true ->
                  # allow the user in the firewall
                  Firewall.allow_mac(conn.assigns[:remote_mac])

                  # log the connection
                  user
                  |> Ecto.build_assoc(:connections)
                  |> Connection.changeset(%{
                    mac_addr: conn.assigns[:remote_mac],
                    ipv4_addr: conn.assigns[:remote_ip4] |> :inet.ntoa |> to_string,
                    ipv6_addr: conn.assigns[:remote_ip6] |> :inet.ntoa |> to_string
                  })
                  |> Repo.insert!

                  # render the response
                  conn
                  |> put_flash(:info, "Authentification réussie")
                  |> render("login.html")
              end
    end
  end

  def logout(conn, _params) do
    Firewall.disallow_mac(conn.assigns[:remote_mac])

    conn
    |> put_flash(:info, "Vous avez été déconnecté")
    |> redirect(to: authentication_path(conn, :login))
  end
end
