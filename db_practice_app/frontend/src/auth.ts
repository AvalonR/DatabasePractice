import { main } from "../wailsjs/go/models";

class AuthStore {
  private user: main.AuthenticatedUser | null = null;

  setUser(user: main.AuthenticatedUser) {
    this.user = user;
  }

  getUser() {
    return this.user;
  }

  can(permission: string): boolean {
    if (!this.user) return false;
    if (this.user.role_name === "Admin") return true;
    return this.user.permissions.includes(permission);
  }

  hasRole(role: string): boolean {
    if (!this.user) return false;
    return this.user.role_name === role;
  }

  logout() {
    this.user = null;
    window.location.reload();
  }
}

export const authStore = new AuthStore();
