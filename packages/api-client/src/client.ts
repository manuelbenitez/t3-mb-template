/** How an ApiClient reaches the backend. */
export interface ApiConfig {
  baseUrl: string;
  getToken?: () => string | null | Promise<string | null>;
}

/** A non-2xx response, carrying the status and the parsed error body when there is one. */
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

/**
 * Typed fetch wrapper for the NestJS backend. `baseUrl` is NEXT_PUBLIC_API_URL
 * (e.g. http://localhost:3001); endpoints carry the full `/api` prefix
 * (e.g. `/api/auth/login`).
 */
export class ApiClient {
  private config: ApiConfig;

  constructor(config: ApiConfig) {
    this.config = config;
  }

  /**
   * The backend origin requests go to.
   *
   * @returns The configured base URL.
   */
  get baseURL(): string {
    return this.config.baseUrl;
  }

  /**
   * Builds the JSON headers, with the bearer token when one is available.
   *
   * @returns The request headers.
   */
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

  /**
   * Sends a request and parses the JSON body.
   *
   * @param endpoint - Path under the base URL, `/api` prefix included.
   * @param options - Fetch options; headers merge over the defaults.
   * @returns The parsed body, or undefined for an empty response.
   * @throws {ApiError} When the response is not 2xx.
   */
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

  /**
   * Sends a GET request.
   *
   * @param endpoint - Path under the base URL.
   * @param options - Query parameters to append.
   * @returns The parsed body.
   */
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

  /**
   * Sends a POST request with a JSON body.
   *
   * @param endpoint - Path under the base URL.
   * @param data - The body, serialized as JSON.
   * @returns The parsed body.
   */
  async post<T>(endpoint: string, data?: unknown): Promise<T> {
    return this.request<T>(endpoint, {
      method: "POST",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  /**
   * Sends a PATCH request with a JSON body.
   *
   * @param endpoint - Path under the base URL.
   * @param data - The body, serialized as JSON.
   * @returns The parsed body.
   */
  async patch<T>(endpoint: string, data?: unknown): Promise<T> {
    return this.request<T>(endpoint, {
      method: "PATCH",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  /**
   * Sends a PUT request with a JSON body.
   *
   * @param endpoint - Path under the base URL.
   * @param data - The body, serialized as JSON.
   * @returns The parsed body.
   */
  async put<T>(endpoint: string, data?: unknown): Promise<T> {
    return this.request<T>(endpoint, {
      method: "PUT",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  /**
   * Sends a DELETE request.
   *
   * @param endpoint - Path under the base URL.
   * @returns The parsed body.
   */
  async delete<T>(endpoint: string): Promise<T> {
    return this.request<T>(endpoint, { method: "DELETE" });
  }
}
