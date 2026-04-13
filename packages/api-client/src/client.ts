/**
 * @acme/api-client
 *
 * Type-safe fetch wrapper for the NestJS backend.
 * baseUrl = NEXT_PUBLIC_API_URL (e.g. http://localhost:3001)
 * Endpoints include the full /api prefix (e.g. /api/auth/login).
 */

export interface ApiConfig {
  baseUrl: string;
  getToken?: () => string | null | Promise<string | null>;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    public statusText: string,
    public data?: unknown,
  ) {
    super(`API Error ${status}: ${statusText}`);
    this.name = "ApiError";
  }
}

export class ApiClient {
  private config: ApiConfig;

  constructor(config: ApiConfig) {
    this.config = config;
  }

  get baseURL(): string {
    return this.config.baseUrl;
  }

  private async getHeaders(): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };

    if (this.config.getToken) {
      const token = await this.config.getToken();
      if (token) {
        headers.Authorization = `Bearer ${token}`;
      }
    }

    return headers;
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    const url = `${this.config.baseUrl}${endpoint}`;
    const headers = await this.getHeaders();

    const response = await fetch(url, {
      ...options,
      headers: { ...headers, ...options.headers },
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => null);
      throw new ApiError(response.status, response.statusText, errorData);
    }

    if (
      response.status === 204 ||
      response.headers.get("content-length") === "0"
    ) {
      return undefined as T;
    }

    const text = await response.text();
    if (!text || text.trim() === "") {
      return undefined as T;
    }

    return JSON.parse(text) as T;
  }

  async get<T>(
    endpoint: string,
    options?: { params?: Record<string, string> },
  ): Promise<T> {
    let url = endpoint;
    if (options?.params) {
      const searchParams = new URLSearchParams(options.params);
      url = `${endpoint}?${searchParams.toString()}`;
    }
    return this.request<T>(url, { method: "GET" });
  }

  async post<T>(endpoint: string, data?: unknown): Promise<T> {
    return this.request<T>(endpoint, {
      method: "POST",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async patch<T>(endpoint: string, data?: unknown): Promise<T> {
    return this.request<T>(endpoint, {
      method: "PATCH",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async put<T>(endpoint: string, data?: unknown): Promise<T> {
    return this.request<T>(endpoint, {
      method: "PUT",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async delete<T>(endpoint: string): Promise<T> {
    return this.request<T>(endpoint, { method: "DELETE" });
  }
}
