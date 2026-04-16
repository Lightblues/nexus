import { Octokit } from '@octokit/rest'
import { logger } from '../../core/Logger'
import type { UploaderConfig, UploadResult } from '@shared/types'

export class GitHubUploader {
  private octokit: Octokit | null = null
  private config: UploaderConfig['github'] | null = null

  configure(config: UploaderConfig['github']): void {
    this.config = config
    this.octokit = new Octokit({ auth: config.token })
  }

  async upload(
    buffer: Buffer,
    path: string,
    filename: string,
    cdnBaseUrl: string
  ): Promise<UploadResult> {
    if (!this.octokit || !this.config) {
      return { success: false, error: 'GitHub not configured' }
    }
    const { owner, repo, branch } = this.config
    const fullPath = path ? `${path}/${filename}` : filename
    const content = buffer.toString('base64')

    try {
      // Check if file exists
      let sha: string | undefined
      try {
        const { data } = await this.octokit.repos.getContent({
          owner,
          repo,
          path: fullPath,
          ref: branch
        })
        if ('sha' in data) {
          sha = data.sha
        }
      } catch {
        // File doesn't exist, that's fine
      }

      // Create or update file
      const response = await this.octokit.repos.createOrUpdateFileContents({
        owner,
        repo,
        path: fullPath,
        message: `Upload ${filename} via EA Nexus`,
        content,
        branch,
        sha
      })

      const cdnUrl = `${cdnBaseUrl}/${owner}/${repo}@${branch}/${fullPath}`
      logger.info(`Uploaded to GitHub: ${fullPath}`)

      return {
        success: true,
        cdnUrl,
        sha: response.data.content?.sha
      }
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error'
      logger.error(`GitHub upload failed: ${error}`)
      return { success: false, error }
    }
  }

  async delete(path: string, sha: string): Promise<{ success: boolean; error?: string }> {
    if (!this.octokit || !this.config) {
      return { success: false, error: 'GitHub not configured' }
    }
    const { owner, repo, branch } = this.config

    try {
      await this.octokit.repos.deleteFile({
        owner,
        repo,
        path,
        message: `Delete ${path} via EA Nexus`,
        sha,
        branch
      })
      logger.info(`Deleted from GitHub: ${path}`)
      return { success: true }
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error'
      logger.error(`GitHub delete failed: ${error}`)
      return { success: false, error }
    }
  }
}

export const githubUploader = new GitHubUploader()
